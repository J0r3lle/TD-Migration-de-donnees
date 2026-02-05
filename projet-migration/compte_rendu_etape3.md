# TD 3 - Migration par étapes PostgreSQL
## Compte rendu - Étape 3 : Migration V3 (Transition/Backfill) et V3.1 (Correction)

**Date :** 5 février 2025  
**Étudiant :** Johan Caruelle  
**Objectif :** Migrer les données existantes et maintenir la cohérence automatique entre anciennes et nouvelles colonnes

---

## 1. Principe de l'étape Transition/Backfill

L'étape **Transition/Backfill** consiste à :
1. **Migrer les données existantes** vers les nouvelles colonnes (backfill)
2. **Maintenir la cohérence automatique** entre anciennes et nouvelles colonnes via des triggers
3. **Préparer la coexistence** des applications V1 et V2 avec des données cohérentes

Après V3, les deux versions de l'application peuvent coexister en production sans conflit de données.

---

## 2. Migration V3 - Backfill et synchronisation

### Objectifs de V3

1. Remplir `customer_full_name` pour toutes les lignes existantes
2. Créer un trigger pour synchroniser automatiquement les modifications
3. Valider la cohérence des données existantes

### Contenu du fichier V3__backfill_full_name.sql

**Fichier : flyway/sql/V3__backfill_full_name.sql**

```sql
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
```

---

## 3. Application de la migration V3

### Commande d'exécution

```bash
docker-compose up flyway
```

### Résultat de l'exécution

```
Flyway OSS Edition 10.22.0 by Redgate
Database: jdbc:postgresql://postgres:5432/globetrotter (PostgreSQL 16.11)
Successfully validated 4 migrations (execution time 00:00.016s)
Current version of schema "public": 2
Migrating schema "public" to version "3 - backfill full name"
Successfully applied 1 migration to schema "public", now at version v3 (execution time 00:00.010s)
```

---

## 4. Vérification de la migration V3

### Vérification du backfill

```sql
SELECT id, customer_first_name, customer_last_name, customer_full_name FROM bookings;
```

**Résultat :**

```
 id | customer_first_name | customer_last_name | customer_full_name 
----+---------------------+--------------------+--------------------
  1 | Jean                | Dupont             | Jean Dupont
  2 | Marie               | Martin             | Marie Martin
  3 | Pierre              | Durand             | Pierre Durand
  4 | Sophie              | Bernard            | Sophie Bernard
  5 | Luc                 | Petit              | Luc Petit
(5 rows)
```

Toutes les lignes existantes ont maintenant leur `customer_full_name` rempli.

### Vérification du trigger

```sql
SELECT trigger_name, event_manipulation, event_object_table 
FROM information_schema.triggers 
WHERE event_object_table = 'bookings';
```

**Résultat :**

```
        trigger_name        | event_manipulation | event_object_table 
----------------------------+--------------------+--------------------
 trigger_sync_customer_name | INSERT             | bookings
 trigger_sync_customer_name | UPDATE             | bookings
(2 rows)
```

Le trigger est bien créé et actif sur INSERT et UPDATE.

---

## 5. Tests de synchronisation

### Test 1 : INSERT V1 (first_name + last_name)

```sql
INSERT INTO bookings (customer_first_name, customer_last_name, customer_email, destination, departure_date, return_date, status)
VALUES ('Alice', 'Dubois', 'alice@email.fr', 'Berlin', '2025-08-01', '2025-08-07', 'PENDING');

SELECT id, customer_first_name, customer_last_name, customer_full_name 
FROM bookings WHERE customer_email = 'alice@email.fr';
```

**Résultat :**

```
 id | customer_first_name | customer_last_name | customer_full_name 
----+---------------------+--------------------+--------------------
  6 | Alice               | Dubois             | Alice Dubois
(1 row)
```

Le trigger a automatiquement créé `customer_full_name = 'Alice Dubois'`.

### Test 2 : INSERT V2 (full_name uniquement)

```sql
INSERT INTO bookings (customer_full_name, customer_email, destination, departure_date, return_date, status)
VALUES ('Bob Martin', 'bob@email.fr', 'Madrid', '2025-09-01', '2025-09-07', 'CONFIRMED');

SELECT id, customer_first_name, customer_last_name, customer_full_name 
FROM bookings WHERE customer_email = 'bob@email.fr';
```

**Résultat :**

```
 id | customer_first_name | customer_last_name | customer_full_name 
----+---------------------+--------------------+--------------------
  7 | Bob                 | Martin             | Bob Martin
(1 row)
```

Le trigger a automatiquement découpé `customer_full_name` en `customer_first_name = 'Bob'` et `customer_last_name = 'Martin'`.

### Test 3 : UPDATE V1 (modification first_name/last_name)

```sql
UPDATE bookings 
SET customer_first_name = 'Jean-Pierre', customer_last_name = 'Dupond'
WHERE id = 1;

SELECT id, customer_first_name, customer_last_name, customer_full_name 
FROM bookings WHERE id = 1;
```

**Résultat :**

```
 id | customer_first_name | customer_last_name | customer_full_name 
----+---------------------+--------------------+--------------------
  1 | Jean-Pierre         | Dupond             | Jean-Pierre Dupond
(1 row)
```

Le trigger a automatiquement mis à jour `customer_full_name` suite à la modification.

### Test 4 : UPDATE V2 (modification full_name) - PROBLÈME DÉTECTÉ

```sql
UPDATE bookings 
SET customer_full_name = 'Marie Leblanc'
WHERE id = 2;

SELECT id, customer_first_name, customer_last_name, customer_full_name 
FROM bookings WHERE id = 2;
```

**Résultat (INCORRECT) :**

```
 id | customer_first_name | customer_last_name | customer_full_name 
----+---------------------+--------------------+--------------------
  2 | Marie               | Martin             | Marie Martin
(1 row)
```

Le trigger n'a **pas** synchronisé correctement. `customer_full_name` devrait être `'Marie Leblanc'` mais est resté à `'Marie Martin'`.

---

## 6. Problème identifié avec le trigger V3

### Analyse du problème

Le trigger de V3 ne gère pas correctement le cas où on UPDATE **uniquement** `customer_full_name`. La logique du trigger exécute systématiquement la première condition qui écrase la valeur de `customer_full_name` avec les anciennes valeurs de `first_name` et `last_name`.

### Cause technique

```sql
-- Cette condition s'exécute toujours lors d'un UPDATE
IF (NEW.customer_first_name IS NOT NULL AND NEW.customer_last_name IS NOT NULL) THEN
    NEW.customer_full_name := NEW.customer_first_name || ' ' || NEW.customer_last_name;
END IF;
```

Lors d'un `UPDATE bookings SET customer_full_name = 'Marie Leblanc' WHERE id = 2` :
1. PostgreSQL charge OLD : `{first: 'Marie', last: 'Martin', full: 'Marie Martin'}`
2. Applique le SET : NEW devient `{first: 'Marie', last: 'Martin', full: 'Marie Leblanc'}`
3. Le trigger s'exécute et voit que `first_name` et `last_name` ne sont pas NULL
4. Il écrase `customer_full_name` avec `'Marie' || ' ' || 'Martin'` = `'Marie Martin'`

---

## 7. Migration V3.1 - Correction du trigger

### Objectif de V3.1

Corriger le trigger pour qu'il détecte quelle colonne a réellement été modifiée et ne synchronise que dans le bon sens.

### Contenu du fichier V3_1__fix_trigger_update.sql

**Fichier : flyway/sql/V3_1__fix_trigger_update.sql**

```sql
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
```

### Points clés de la correction

1. **Détection de modification** : Utilisation de `IS DISTINCT FROM` pour comparer OLD et NEW
2. **Ordre de priorité** : Le cas 1 (V1) s'exécute en premier, le cas 2 (V2) vérifie qu'il n'est pas déjà synchronisé
3. **Variable TG_OP** : Permet de détecter si c'est un INSERT (pas de OLD) ou un UPDATE

---

## 8. Application de la migration V3.1

### Commande d'exécution

```bash
docker-compose up flyway
```

### Résultat de l'exécution

```
Flyway OSS Edition 10.22.0 by Redgate
Database: jdbc:postgresql://postgres:5432/globetrotter (PostgreSQL 16.11)
Successfully validated 5 migrations (execution time 00:00.017s)
Current version of schema "public": 3
Migrating schema "public" to version "3.1 - fix trigger update"
Successfully applied 1 migration to schema "public", now at version v3.1 (execution time 00:00.008s)
```

---

## 9. Tests de validation après V3.1

### Test UPDATE V2 (corrigé)

```sql
UPDATE bookings 
SET customer_full_name = 'Marie Leblanc'
WHERE id = 2;

SELECT id, customer_first_name, customer_last_name, customer_full_name 
FROM bookings WHERE id = 2;
```

**Résultat (CORRECT) :**

```
 id | customer_first_name | customer_last_name | customer_full_name 
----+---------------------+--------------------+--------------------
  2 | Marie               | Leblanc            | Marie Leblanc
(1 row)
```

Le trigger fonctionne maintenant correctement :
- `customer_full_name` a été mis à jour à `'Marie Leblanc'`
- `customer_first_name` reste `'Marie'`
- `customer_last_name` a été mis à jour à `'Leblanc'`

---

## 10. Récapitulatif complet des tests après V3.1

| Test | Type | Entrée | Résultat attendu | Status |
|------|------|--------|------------------|--------|
| Backfill | Migration | 5 lignes avec first/last | 5 lignes avec full_name | OK |
| INSERT V1 | INSERT | first='Alice', last='Dubois' | full='Alice Dubois' | OK |
| INSERT V2 | INSERT | full='Bob Martin' | first='Bob', last='Martin' | OK |
| UPDATE V1 | UPDATE | first='Jean-Pierre', last='Dupond' | full='Jean-Pierre Dupond' | OK |
| UPDATE V2 | UPDATE | full='Marie Leblanc' | first='Marie', last='Leblanc' | OK |

Tous les tests passent avec succès.

---

## 11. État final des données après V3.1

```sql
SELECT id, customer_first_name, customer_last_name, customer_full_name FROM bookings;
```

**Résultat :**

```
 id | customer_first_name | customer_last_name | customer_full_name 
----+---------------------+--------------------+--------------------
  1 | Jean-Pierre         | Dupond             | Jean-Pierre Dupond
  2 | Marie               | Leblanc            | Marie Leblanc
  3 | Pierre              | Durand             | Pierre Durand
  4 | Sophie              | Bernard            | Sophie Bernard
  5 | Luc                 | Petit              | Luc Petit
  6 | Alice               | Dubois             | Alice Dubois
  7 | Bob                 | Martin             | Bob Martin
(7 rows)
```

Toutes les colonnes sont cohérentes et synchronisées.

---

## 12. Analyse de compatibilité après V3.1

### Application V1 (ancienne version)

**Comportement :**
- INSERT avec `first_name` et `last_name` → Le trigger remplit automatiquement `full_name`
- UPDATE de `first_name` ou `last_name` → Le trigger met à jour `full_name`
- L'application V1 ignore complètement `customer_full_name`

**Exemple de code V1 :**
```python
# INSERT V1
cursor.execute("""
    INSERT INTO bookings (customer_first_name, customer_last_name, customer_email, ...)
    VALUES (%s, %s, %s, ...)
""", (first_name, last_name, email, ...))
# customer_full_name est rempli automatiquement par le trigger
```

### Application V2 (nouvelle version)

**Comportement :**
- INSERT avec `customer_full_name` → Le trigger découpe automatiquement en `first_name` et `last_name`
- UPDATE de `customer_full_name` → Le trigger met à jour `first_name` et `last_name`
- L'application V2 peut ignorer `customer_first_name` et `customer_last_name`

**Exemple de code V2 :**
```python
# INSERT V2
cursor.execute("""
    INSERT INTO bookings (customer_full_name, customer_email, ...)
    VALUES (%s, %s, ...)
""", (full_name, email, ...))
# customer_first_name et customer_last_name sont remplis par le trigger
```

### Coexistence V1 et V2

Les deux versions peuvent fonctionner simultanément en production sans conflit :
- V1 écrit dans `first_name`/`last_name`, V2 lit dans `full_name` → Cohérent grâce au trigger
- V2 écrit dans `full_name`, V1 lit dans `first_name`/`last_name` → Cohérent grâce au trigger

---

## 13. Fonctionnement technique du trigger corrigé

### Logique du trigger V3.1

```
AVANT INSERT OU UPDATE:
  
  1. Vérifier si first_name ou last_name a changé:
     SI OUI → Mettre à jour full_name = first_name || ' ' || last_name
  
  2. Vérifier si full_name a changé:
     SI OUI ET full_name != (first_name || ' ' || last_name):
        → Découper full_name en first_name et last_name
```

### Exemples de flux

**Flux 1 : INSERT V1**
```
INPUT: first_name='Alice', last_name='Dubois', full_name=NULL
│
├─ Cas 1: first_name et last_name fournis
│  └─> full_name = 'Alice' || ' ' || 'Dubois' = 'Alice Dubois'
│
OUTPUT: first_name='Alice', last_name='Dubois', full_name='Alice Dubois'
```

**Flux 2 : UPDATE V2 (modification de full_name)**
```
OLD: first_name='Marie', last_name='Martin', full_name='Marie Martin'
INPUT: full_name='Marie Leblanc'
│
├─ Cas 1: first_name et last_name inchangés → SKIP
│
├─ Cas 2: full_name a changé
│  └─> full_name='Marie Leblanc' != 'Marie Martin'
│  └─> Découper: first_name='Marie', last_name='Leblanc'
│
OUTPUT: first_name='Marie', last_name='Leblanc', full_name='Marie Leblanc'
```

**Flux 3 : UPDATE V1 (modification de first_name)**
```
OLD: first_name='Jean', last_name='Dupont', full_name='Jean Dupont'
INPUT: first_name='Jean-Pierre'
│
├─ Cas 1: first_name a changé
│  └─> full_name = 'Jean-Pierre' || ' ' || 'Dupont' = 'Jean-Pierre Dupont'
│
├─ Cas 2: full_name a changé mais déjà synchronisé par Cas 1 → SKIP
│
OUTPUT: first_name='Jean-Pierre', last_name='Dupont', full_name='Jean-Pierre Dupont'
```

---

## 14. Opérateur IS DISTINCT FROM

### Explication

L'opérateur `IS DISTINCT FROM` est utilisé pour comparer des valeurs en tenant compte des NULL :

```sql
-- Comparaison classique (=)
NULL = NULL      → NULL (pas TRUE)
'A' = 'A'        → TRUE
'A' = 'B'        → FALSE

-- IS DISTINCT FROM
NULL IS DISTINCT FROM NULL      → FALSE (ils sont identiques)
'A' IS DISTINCT FROM 'A'        → FALSE (ils sont identiques)
'A' IS DISTINCT FROM 'B'        → TRUE (ils sont différents)
'A' IS DISTINCT FROM NULL       → TRUE (ils sont différents)
```

Dans le contexte du trigger :
```sql
OLD.customer_first_name IS DISTINCT FROM NEW.customer_first_name
```

Cette condition est TRUE si `customer_first_name` a été modifié (y compris de NULL vers une valeur ou vice-versa).

---

## 15. Leçons apprises

### Complexité des triggers bidirectionnels

Les triggers bidirectionnels (qui synchronisent dans les deux sens) sont complexes à implémenter correctement car :
1. Il faut détecter quelle colonne a été modifiée
2. Il faut éviter les boucles infinies
3. Il faut gérer les cas limites (NULL, espaces multiples, noms composés)

### Importance des tests

Le test UPDATE V2 a révélé un bug qui n'était pas évident à la lecture du code. Les tests sont essentiels pour valider les triggers.

### Alternative : Application-level sync

Une alternative aurait été de gérer la synchronisation au niveau applicatif :
- L'application V1 écrit dans `first_name`/`last_name` ET `full_name`
- L'application V2 écrit dans `full_name` ET découpe en `first_name`/`last_name`

**Avantages :** Plus simple, plus prévisible, pas de logique complexe en base
**Inconvénients :** Nécessite de modifier l'application, risque d'oubli

---

## 16. Migrations appliquées

```
V1     - init_schema         : Création de la table bookings (version initiale)
V1.1   - seed_data           : Insertion des données de test
V2     - expand_bookings     : Ajout des nouvelles colonnes
V3     - backfill_full_name  : Migration des données et trigger (bug)
V3.1   - fix_trigger_update  : Correction du trigger (ACTUELLE)
```

---

## 17. Schéma actuel

**Table bookings :**
- Anciennes colonnes : `customer_first_name`, `customer_last_name`, `status`
- Nouvelles colonnes : `customer_full_name`, `last_modified_at`
- Trigger actif : `trigger_sync_customer_name` (BEFORE INSERT OR UPDATE)

**Table booking_status_ref :**
- 3 statuts de référence : PENDING, CONFIRMED, CANCELLED

**Données :**
- 7 réservations avec synchronisation bidirectionnelle complète

---

## 18. Prochaine étape : V4 (Contract)

La migration V4 sera la dernière étape du pattern expand-contract. Elle devra :

1. **Rendre customer_full_name NOT NULL**
   - Maintenant que toutes les lignes sont remplies, on peut ajouter la contrainte

2. **Supprimer les anciennes colonnes**
   - `customer_first_name`
   - `customer_last_name`

3. **Supprimer le trigger** (optionnel)
   - Une fois les anciennes colonnes supprimées, le trigger n'est plus nécessaire

4. **Créer une contrainte de clé étrangère pour status** (optionnel)
   - Remplacer `status` VARCHAR par `status_code` avec FK vers `booking_status_ref`

Après V4, seule l'application V2 pourra fonctionner. L'application V1 sera incompatible.

---

## 19. Conclusion de l'étape V3

La migration V3 (avec sa correction V3.1) a été appliquée avec succès. Le système est maintenant dans un état stable où :

- Les données existantes ont été migrées
- Les deux versions de l'application peuvent coexister
- La synchronisation automatique garantit la cohérence
- Tous les scénarios (INSERT V1, INSERT V2, UPDATE V1, UPDATE V2) fonctionnent correctement

Le projet est prêt pour la dernière étape : V4 (Contract).
