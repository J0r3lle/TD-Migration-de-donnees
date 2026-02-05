-- Migration V2 : Étape EXPAND
-- Ajout des nouvelles colonnes sans supprimer les anciennes
-- Permet la compatibilité avec l'application V1 et V2

-- 1. Ajout de la colonne customer_full_name (nullable pour l'instant)
ALTER TABLE bookings 
ADD COLUMN customer_full_name VARCHAR(200);

-- 2. Ajout de la colonne last_modified_at avec valeur par défaut
ALTER TABLE bookings 
ADD COLUMN last_modified_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- 3. Création de la table de référence des statuts
CREATE TABLE booking_status_ref (
    code VARCHAR(50) PRIMARY KEY,
    label VARCHAR(255) NOT NULL
);

-- 4. Insertion des statuts de référence
INSERT INTO booking_status_ref (code, label) VALUES
    ('PENDING', 'En attente de paiement'),
    ('CONFIRMED', 'Réservation confirmée'),
    ('CANCELLED', 'Réservation annulée');

-- 5. Ajout d'un commentaire pour documenter la future migration
COMMENT ON COLUMN bookings.status IS 
'Colonne legacy. Sera remplacée par une référence à booking_status_ref.code dans V4';

COMMENT ON COLUMN bookings.customer_full_name IS 
'Nouvelle colonne qui remplacera customer_first_name et customer_last_name dans V4';

-- 6. Création d'un index sur la nouvelle colonne
CREATE INDEX idx_bookings_full_name ON bookings(customer_full_name);