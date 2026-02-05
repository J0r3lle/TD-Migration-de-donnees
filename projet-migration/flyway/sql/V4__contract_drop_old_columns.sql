-- Migration V4 : Étape CONTRACT
-- Suppression des anciennes colonnes et finalisation du nouveau modèle
-- ATTENTION : Cette migration rend l'application V1 incompatible

-- 1. Rendre customer_full_name NOT NULL
-- Toutes les lignes ont désormais une valeur grâce au backfill V3
ALTER TABLE bookings 
ALTER COLUMN customer_full_name SET NOT NULL;

-- 2. Supprimer le trigger de synchronisation (devenu inutile)
DROP TRIGGER IF EXISTS trigger_sync_customer_name ON bookings;
DROP FUNCTION IF EXISTS sync_customer_name();

-- 3. Supprimer les anciennes colonnes
ALTER TABLE bookings 
DROP COLUMN customer_first_name,
DROP COLUMN customer_last_name;

-- 4. Créer une colonne status_code avec FK vers booking_status_ref
-- D'abord, ajouter la nouvelle colonne (nullable temporairement)
ALTER TABLE bookings 
ADD COLUMN status_code VARCHAR(50);

-- 5. Migrer les données de status vers status_code
UPDATE bookings 
SET status_code = status;

-- 6. Vérifier que toutes les valeurs sont valides
DO $$
DECLARE
    invalid_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO invalid_count
    FROM bookings
    WHERE status_code NOT IN (SELECT code FROM booking_status_ref);
    
    IF invalid_count > 0 THEN
        RAISE EXCEPTION 'Erreur : % lignes avec un status_code invalide', invalid_count;
    END IF;
END $$;

-- 7. Rendre status_code NOT NULL et ajouter la contrainte FK
ALTER TABLE bookings 
ALTER COLUMN status_code SET NOT NULL;

ALTER TABLE bookings 
ADD CONSTRAINT fk_booking_status 
FOREIGN KEY (status_code) REFERENCES booking_status_ref(code);

-- 8. Supprimer l'ancienne colonne status
ALTER TABLE bookings 
DROP COLUMN status;

-- 9. Renommer status_code en status pour garder le même nom de colonne
ALTER TABLE bookings 
RENAME COLUMN status_code TO status;

-- 10. Créer un index sur la nouvelle colonne status
CREATE INDEX idx_bookings_status_fk ON bookings(status);

-- 11. Ajouter des commentaires pour documenter les changements
COMMENT ON COLUMN bookings.customer_full_name IS 
'Nom complet du client (remplace customer_first_name et customer_last_name)';

COMMENT ON COLUMN bookings.status IS 
'Code du statut de la réservation (FK vers booking_status_ref)';

-- 12. Supprimer l'ancien index devenu inutile (si vous l'aviez créé)
DROP INDEX IF EXISTS idx_bookings_full_name;