-- Migration V3 : Étape TRANSITION / BACKFILL
-- Migration des données existantes et synchronisation automatique
-- Permet la coexistence de V1 et V2 avec cohérence des données

-- 1. Backfill : Remplir customer_full_name pour toutes les lignes existantes
UPDATE bookings
SET customer_full_name = customer_first_name || ' ' || customer_last_name
WHERE customer_full_name IS NULL;

-- 2. Création d'une fonction trigger pour maintenir la cohérence
CREATE OR REPLACE FUNCTION sync_customer_name()
RETURNS TRIGGER AS $$
BEGIN
    -- Si on modifie first_name ou last_name, mettre à jour full_name
    IF (NEW.customer_first_name IS NOT NULL AND NEW.customer_last_name IS NOT NULL) THEN
        NEW.customer_full_name := NEW.customer_first_name || ' ' || NEW.customer_last_name;
    END IF;
    
    -- Si on modifie full_name, essayer de découper (optionnel, pour compatibilité V2 -> V1)
    -- Cette partie est optionnelle car V2 n'a pas besoin de rétro-compatibilité vers V1
    IF (NEW.customer_full_name IS NOT NULL AND 
        (NEW.customer_first_name IS NULL OR NEW.customer_last_name IS NULL)) THEN
        -- Découper le nom complet (simple : au premier espace)
        NEW.customer_first_name := split_part(NEW.customer_full_name, ' ', 1);
        NEW.customer_last_name := CASE 
            WHEN position(' ' IN NEW.customer_full_name) > 0 
            THEN substring(NEW.customer_full_name FROM position(' ' IN NEW.customer_full_name) + 1)
            ELSE ''
        END;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Création du trigger sur INSERT et UPDATE
CREATE TRIGGER trigger_sync_customer_name
    BEFORE INSERT OR UPDATE ON bookings
    FOR EACH ROW
    EXECUTE FUNCTION sync_customer_name();

-- 4. Validation des valeurs de status (optionnel mais recommandé)
-- Vérifier que toutes les valeurs actuelles de status sont valides
DO $$
DECLARE
    invalid_status_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO invalid_status_count
    FROM bookings
    WHERE status NOT IN (SELECT code FROM booking_status_ref);
    
    IF invalid_status_count > 0 THEN
        RAISE NOTICE 'Attention : % lignes avec un status invalide détecté', invalid_status_count;
        -- On pourrait corriger automatiquement ou lever une erreur
        -- Pour l'instant, on se contente d'un avertissement
    END IF;
END $$;

-- 5. Ajout d'un commentaire pour documenter le trigger
COMMENT ON TRIGGER trigger_sync_customer_name ON bookings IS 
'Maintient la cohérence entre customer_first_name/customer_last_name et customer_full_name';