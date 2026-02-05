-- Migration V3.1 : Correction du trigger de synchronisation
-- Le trigger ne gérait pas correctement les UPDATE de customer_full_name seul

-- 1. Supprimer l'ancien trigger et fonction
DROP TRIGGER IF EXISTS trigger_sync_customer_name ON bookings;
DROP FUNCTION IF EXISTS sync_customer_name();

-- 2. Recréer la fonction trigger améliorée
CREATE OR REPLACE FUNCTION sync_customer_name()
RETURNS TRIGGER AS $$
BEGIN
    -- Détecter quel champ a été modifié pour synchroniser correctement
    
    -- Cas 1: Modification de first_name ou last_name (scénario V1)
    IF (TG_OP = 'INSERT' OR 
        OLD.customer_first_name IS DISTINCT FROM NEW.customer_first_name OR 
        OLD.customer_last_name IS DISTINCT FROM NEW.customer_last_name) THEN
        
        IF (NEW.customer_first_name IS NOT NULL AND NEW.customer_last_name IS NOT NULL) THEN
            NEW.customer_full_name := NEW.customer_first_name || ' ' || NEW.customer_last_name;
        END IF;
    END IF;
    
    -- Cas 2: Modification de full_name uniquement (scénario V2)
    IF (TG_OP = 'INSERT' OR OLD.customer_full_name IS DISTINCT FROM NEW.customer_full_name) THEN
        
        -- Vérifier que ce n'est pas déjà synchronisé par le cas 1
        IF (NEW.customer_full_name IS NOT NULL AND 
            NEW.customer_full_name != COALESCE(NEW.customer_first_name || ' ' || NEW.customer_last_name, '')) THEN
            
            -- Découper le nom complet
            NEW.customer_first_name := split_part(NEW.customer_full_name, ' ', 1);
            NEW.customer_last_name := CASE 
                WHEN position(' ' IN NEW.customer_full_name) > 0 
                THEN substring(NEW.customer_full_name FROM position(' ' IN NEW.customer_full_name) + 1)
                ELSE ''
            END;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Recréer le trigger
CREATE TRIGGER trigger_sync_customer_name
    BEFORE INSERT OR UPDATE ON bookings
    FOR EACH ROW
    EXECUTE FUNCTION sync_customer_name();

-- 4. Ajouter un commentaire
COMMENT ON TRIGGER trigger_sync_customer_name ON bookings IS 
'Maintient la cohérence bidirectionnelle entre customer_first_name/customer_last_name et customer_full_name';