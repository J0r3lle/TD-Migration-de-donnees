# TD 3 - Migration par étapes PostgreSQL
## Compte rendu - Étape 4 : Migration V4 (Contract)

**Date :** 5 février 2025  
**Étudiant :** Johan Caruelle  
**Objectif :** Finaliser le nouveau modèle et supprimer les anciennes colonnes

---

## 1. Principe de l'étape Contract

L'étape **Contract** est la dernière étape du pattern expand-contract. Elle consiste à :
1. **Nettoyer l'ancien schéma** en supprimant les colonnes obsolètes
2. **Finaliser le nouveau modèle** en rendant les nouvelles colonnes obligatoires
3. **Ajouter les contraintes d'intégrité** (NOT NULL, FK)
4. **Supprimer les mécanismes de transition** (triggers)

Après V4, **seule l'application V2 peut fonctionner**. L'application V1 devient incompatible.

---

## 2. Migration V4 - Nettoyage et finalisation

### Objectifs de V4

1. Rendre `customer_full_name` NOT NULL
2. Supprimer le trigger de synchronisation (devenu inutile)
3. Supprimer les colonnes `customer_first_name` et `customer_last_name`
4. Créer une contrainte de clé étrangère pour `status`
5. Documenter les changements

### Contenu du fichier V4__contract_drop_old_columns.sql

**Fichier : flyway/sql/V4__contract_drop_old_columns.sql**

```sql
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
```

---

## 3. Application de la migration V4

### Commande d'exécution

```bash
docker-compose up flyway
```

### Résultat de l'exécution

```
Flyway OSS Edition 10.22.0 by Redgate
Database: jdbc:postgresql://postgres:5432/globetrotter (PostgreSQL 16.11)
Successfully validated 6 migrations (execution time 00:00.018s)
Current version of schema "public": 3.1
Migrating schema "public" to version "4 - contract drop old columns"
Successfully applied 1 migration to schema "public", now at version v4 (execution time 00:00.012s)
```

---

## 4. Vérifications après migration V4

### Structure finale de la table bookings

```sql
\d bookings
```

**Résultat :**

```
Table "public.bookings"
       Column       |            Type             | Collation | Nullable |          Default
--------------------+-----------------------------+-----------+----------+----------------------------------
 id                 | bigint                      |           | not null | nextval('bookings_id_seq'::regclass)
 customer_email     | character varying(255)      |           | not null |
 destination        | character varying(255)      |           | not null |
 departure_date     | date                        |           | not null |
 return_date        | date                        |           | not null |
 created_at         | timestamp without time zone |           | not null | CURRENT_TIMESTAMP
 customer_full_name | character varying(200)      |           | not null |
 last_modified_at   | timestamp without time zone |           | not null | CURRENT_TIMESTAMP
 status             | character varying(50)       |           | not null |

Indexes:
    "bookings_pkey" PRIMARY KEY, btree (id)
    "idx_bookings_departure_date" btree (departure_date)
    "idx_bookings_email" btree (customer_email)
    "idx_bookings_status_fk" btree (status)

Foreign-key constraints:
    "fk_booking_status" FOREIGN KEY (status) REFERENCES booking_status_ref(code)
```

**Observations importantes :**
- `customer_first_name` et `customer_last_name` ont été supprimés
- `customer_full_name` est maintenant NOT NULL
- `status` a une contrainte de clé étrangère vers `booking_status_ref(code)`
- 9 colonnes au total (au lieu de 11 avant V4)

### Détail des colonnes

```sql
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'bookings' 
ORDER BY ordinal_position;
```

**Résultat :**

```
    column_name     |          data_type          | is_nullable 
--------------------+-----------------------------+-------------
 id                 | bigint                      | NO
 customer_email     | character varying           | NO
 destination        | character varying           | NO
 departure_date     | date                        | NO
 return_date        | date                        | NO
 created_at         | timestamp without time zone | NO
 customer_full_name | character varying           | NO
 last_modified_at   | timestamp without time zone | NO
 status             | character varying           | NO
(9 rows)
```

Toutes les colonnes sont NOT NULL, ce qui garantit l'intégrité des données.

### Vérification des données

```sql
SELECT id, customer_full_name, status FROM bookings;
```

**Résultat :**

```
 id | customer_full_name |  status   
----+--------------------+-----------
  3 | Pierre Durand      | CONFIRMED
  4 | Sophie Bernard     | CANCELLED
  5 | Luc Petit          | CONFIRMED
  6 | Alice Dubois       | PENDING
  7 | Bob Martin         | CONFIRMED
  1 | Jean-Pierre Dupond | CONFIRMED
  2 | Marie Leblanc      | PENDING
(7 rows)
```

Toutes les données sont intactes et cohérentes.

### Vérification de la suppression du trigger

```sql
SELECT trigger_name FROM information_schema.triggers 
WHERE event_object_table = 'bookings';
```

**Résultat :**

```
 trigger_name 
--------------
(0 rows)
```

Le trigger de synchronisation a bien été supprimé.

### Vérification de la contrainte de clé étrangère

```sql
SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
WHERE tc.table_name = 'bookings' AND tc.constraint_type = 'FOREIGN KEY';
```

**Résultat :**

```
  constraint_name   | table_name | column_name | foreign_table_name | foreign_column_name 
--------------------+------------+-------------+--------------------+---------------------
 fk_booking_status  | bookings   | status      | booking_status_ref | code
```

La contrainte de clé étrangère est bien créée et active.

---

## 5. Tests de validation

### Test 1 : INSERT avec l'ancien modèle (V1) - Doit échouer

```sql
INSERT INTO bookings (customer_first_name, customer_last_name, customer_email, destination, departure_date, return_date, status)
VALUES ('Test', 'User', 'test@email.fr', 'Paris', '2025-10-01', '2025-10-05', 'PENDING');
```

**Résultat (ERREUR ATTENDUE) :**

```
ERROR:  column "customer_first_name" of relation "bookings" does not exist
LINE 1: INSERT INTO bookings (customer_first_name, customer_last_nam...
                              ^
```

L'application V1 ne peut plus fonctionner. C'est le comportement attendu après l'étape Contract.

### Test 2 : INSERT avec le nouveau modèle (V2) - Doit réussir

```sql
INSERT INTO bookings (customer_full_name, customer_email, destination, departure_date, return_date, status)
VALUES ('Claire Dupuis', 'claire@email.fr', 'Barcelone', '2025-11-01', '2025-11-07', 'CONFIRMED');

SELECT id, customer_full_name, status FROM bookings WHERE customer_email = 'claire@email.fr';
```

**Résultat (SUCCÈS) :**

```
INSERT 0 1

 id | customer_full_name |  status   
----+--------------------+-----------
  8 | Claire Dupuis      | CONFIRMED
(1 row)
```

L'application V2 fonctionne parfaitement avec le nouveau modèle.

### Test 3 : Contrainte FK sur status - Doit bloquer les statuts invalides

```sql
INSERT INTO bookings (customer_full_name, customer_email, destination, departure_date, return_date, status)
VALUES ('Test User', 'test2@email.fr', 'Paris', '2025-12-01', '2025-12-05', 'INVALID_STATUS');
```

**Résultat (ERREUR ATTENDUE) :**

```
ERROR:  insert or update on table "bookings" violates foreign key constraint "fk_booking_status"
DETAIL:  Key (status)=(INVALID_STATUS) is not present in table "booking_status_ref".
```

La contrainte de clé étrangère protège l'intégrité des données en bloquant les statuts invalides.

---

## 6. Comparaison avant/après V4

### Avant V4 (après V3.1)

| Colonne | Type | Nullable | Contraintes |
|---------|------|----------|-------------|
| id | bigint | NOT NULL | PK |
| customer_first_name | varchar(100) | NOT NULL | - |
| customer_last_name | varchar(100) | NOT NULL | - |
| customer_email | varchar(255) | NOT NULL | - |
| destination | varchar(255) | NOT NULL | - |
| departure_date | date | NOT NULL | - |
| return_date | date | NOT NULL | - |
| status | varchar(50) | NOT NULL | - |
| created_at | timestamp | NOT NULL | DEFAULT |
| customer_full_name | varchar(200) | NULL | - |
| last_modified_at | timestamp | NOT NULL | DEFAULT |

**Trigger actif :** `trigger_sync_customer_name` (synchronisation bidirectionnelle)

### Après V4

| Colonne | Type | Nullable | Contraintes |
|---------|------|----------|-------------|
| id | bigint | NOT NULL | PK |
| customer_email | varchar(255) | NOT NULL | - |
| destination | varchar(255) | NOT NULL | - |
| departure_date | date | NOT NULL | - |
| return_date | date | NOT NULL | - |
| created_at | timestamp | NOT NULL | DEFAULT |
| customer_full_name | varchar(200) | NOT NULL | - |
| last_modified_at | timestamp | NOT NULL | DEFAULT |
| status | varchar(50) | NOT NULL | FK → booking_status_ref(code) |

**Trigger :** Aucun

**Changements :**
- Suppression de 2 colonnes (`customer_first_name`, `customer_last_name`)
- `customer_full_name` : NULL → NOT NULL
- `status` : Sans contrainte → FK vers `booking_status_ref`
- Suppression du trigger de synchronisation

---

## 7. Évolution du schéma à travers les migrations

### Chronologie complète

```
V1 (État initial)
├── customer_first_name (NOT NULL)
├── customer_last_name (NOT NULL)
└── status (VARCHAR, texte libre)

V2 (Expand)
├── customer_first_name (NOT NULL) ◄─ Conservé
├── customer_last_name (NOT NULL)  ◄─ Conservé
├── customer_full_name (NULL)      ◄─ AJOUTÉ
├── last_modified_at (NOT NULL)    ◄─ AJOUTÉ
├── status (VARCHAR, texte libre)  ◄─ Conservé
└── booking_status_ref (table)     ◄─ AJOUTÉE

V3 (Transition)
├── customer_first_name (NOT NULL) ◄─ Synchronisé
├── customer_last_name (NOT NULL)  ◄─ Synchronisé
├── customer_full_name (NOT NULL)  ◄─ Rempli par backfill
└── Trigger bidirectionnel         ◄─ AJOUTÉ

V4 (Contract)
├── customer_first_name            ◄─ SUPPRIMÉ
├── customer_last_name             ◄─ SUPPRIMÉ
├── customer_full_name (NOT NULL)  ◄─ Conservé
├── status → status_code (FK)      ◄─ Contraint
└── Trigger                        ◄─ SUPPRIMÉ
```

---

## 8. Analyse de compatibilité après V4

### Application V1 - INCOMPATIBLE

**Requête typique V1 :**
```sql
INSERT INTO bookings (customer_first_name, customer_last_name, customer_email, ...)
VALUES ('Alice', 'Dubois', 'alice@email.fr', ...);
```

**Erreur :**
```
ERROR: column "customer_first_name" of relation "bookings" does not exist
```

**Actions nécessaires :**
- L'application V1 doit être complètement retirée de production
- Tous les serveurs doivent être mis à jour vers V2
- Aucun rollback n'est possible sans restauration complète de la base

### Application V2 - COMPATIBLE

**Requête typique V2 :**
```sql
INSERT INTO bookings (customer_full_name, customer_email, destination, ...)
VALUES ('Alice Dubois', 'alice@email.fr', 'Berlin', ...);
```

**Résultat :** Fonctionne parfaitement.

**Code d'exemple V2 (Python) :**
```python
# Application V2 - Utilise le nouveau modèle
def create_booking(full_name, email, destination, departure, return_date, status):
    cursor.execute("""
        INSERT INTO bookings (
            customer_full_name, 
            customer_email, 
            destination, 
            departure_date, 
            return_date, 
            status
        )
        VALUES (%s, %s, %s, %s, %s, %s)
    """, (full_name, email, destination, departure, return_date, status))
```

---

## 9. Avantages de la contrainte FK sur status

### Protection des données

La contrainte FK garantit que seuls les statuts valides peuvent être insérés :

```sql
-- Valide (OK)
INSERT INTO bookings (..., status) VALUES (..., 'CONFIRMED');

-- Invalide (ERREUR)
INSERT INTO bookings (..., status) VALUES (..., 'CONFIRMD'); -- Typo
INSERT INTO bookings (..., status) VALUES (..., 'APPROVED'); -- N'existe pas
```

### Évolution facilitée

Pour ajouter un nouveau statut, il suffit de l'ajouter dans `booking_status_ref` :

```sql
INSERT INTO booking_status_ref (code, label) 
VALUES ('ON_HOLD', 'Réservation en attente de validation');
```

Tous les bookings peuvent immédiatement utiliser ce nouveau statut.

### Cascade et maintenance

On peut ajouter des options CASCADE si nécessaire :

```sql
-- Exemple : Remplacer un statut obsolète
UPDATE bookings SET status = 'CONFIRMED' WHERE status = 'OLD_STATUS';
DELETE FROM booking_status_ref WHERE code = 'OLD_STATUS';
```

---

## 10. Stratégie de déploiement pour V4

### Pré-requis avant V4

Avant d'appliquer V4, il faut s'assurer que :
1. L'application V2 est déployée sur **100% des serveurs**
2. L'application V1 est **complètement retirée** de production
3. Aucun batch/script n'utilise plus l'ancien modèle
4. Les tests de charge ont validé V2

### Fenêtre de déploiement

Bien que V4 soit rapide (quelques secondes), il est recommandé de :
- Planifier une fenêtre de maintenance courte (5-10 minutes)
- Avoir un plan de rollback (restauration complète de la base)
- Surveiller les métriques après déploiement

### Rollback

**Attention :** Le rollback après V4 est complexe :
- Il faut restaurer une sauvegarde de la base avant V4
- Ou recréer manuellement les colonnes supprimées
- Les données insérées après V4 seront perdues

C'est pourquoi il est crucial de valider V3 en production avant de passer à V4.

---

## 11. Chronologie complète du pattern Expand-Contract

### Phase 1 : Préparation (V1 → V2)

**Durée :** Quelques minutes
**Impact :** Aucun
**Action :** Ajout des nouvelles colonnes

### Phase 2 : Transition (V2 → V3)

**Durée :** Dépend du volume de données
**Impact :** Aucun
**Action :** Migration des données et création du trigger

### Phase 3 : Coexistence (V3 en production)

**Durée :** Jours/semaines (selon la confiance)
**Impact :** Aucun
**Action :** Déploiement progressif de l'application V2

### Phase 4 : Nettoyage (V3 → V4)

**Durée :** Quelques secondes
**Impact :** Application V1 incompatible
**Action :** Suppression des anciennes colonnes

---

## 12. Métriques et performance

### Taille des données

**Avant V4 :**
- 11 colonnes par ligne
- Colonnes redondantes (`first_name` + `last_name` + `full_name`)

**Après V4 :**
- 9 colonnes par ligne
- Réduction de ~18% du nombre de colonnes
- Économie d'espace disque

### Index

**Avant V4 :**
- 4 index : PK, email, status, departure_date, full_name
- `full_name` index créé en V2, supprimé en V4

**Après V4 :**
- 4 index : PK, email, status_fk, departure_date
- Index optimisés pour les requêtes V2

### Contraintes

**Avant V4 :**
- 1 contrainte : Primary Key
- Pas de validation sur `status`

**Après V4 :**
- 2 contraintes : Primary Key, Foreign Key
- Validation automatique des statuts

---

## 13. Documentation technique finale

### Table bookings (version finale)

```sql
-- Table principale des réservations
CREATE TABLE bookings (
    id BIGSERIAL PRIMARY KEY,
    customer_email VARCHAR(255) NOT NULL,
    destination VARCHAR(255) NOT NULL,
    departure_date DATE NOT NULL,
    return_date DATE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    customer_full_name VARCHAR(200) NOT NULL,
    last_modified_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) NOT NULL,
    
    CONSTRAINT fk_booking_status 
        FOREIGN KEY (status) REFERENCES booking_status_ref(code)
);

-- Index pour optimiser les requêtes
CREATE INDEX idx_bookings_departure_date ON bookings(departure_date);
CREATE INDEX idx_bookings_email ON bookings(customer_email);
CREATE INDEX idx_bookings_status_fk ON bookings(status);
```

### Table booking_status_ref

```sql
-- Table de référence des statuts
CREATE TABLE booking_status_ref (
    code VARCHAR(50) PRIMARY KEY,
    label VARCHAR(255) NOT NULL
);

-- Statuts valides
INSERT INTO booking_status_ref (code, label) VALUES
    ('PENDING', 'En attente de paiement'),
    ('CONFIRMED', 'Réservation confirmée'),
    ('CANCELLED', 'Réservation annulée');
```

---

## 14. Leçons apprises

### Ce qui a bien fonctionné

1. **Pattern Expand-Contract**
   - Aucune interruption de service
   - Migration progressive et contrôlée
   - Validation à chaque étape

2. **Trigger de synchronisation**
   - Cohérence automatique pendant la transition
   - Coexistence V1/V2 transparente

3. **Contraintes d'intégrité**
   - FK sur status empêche les données invalides
   - NOT NULL garantit la qualité des données

### Défis rencontrés

1. **Bug du trigger en V3**
   - Le trigger initial ne gérait pas correctement les UPDATE V2
   - Résolu par V3.1 avec détection de modification

2. **Complexité du trigger**
   - Logique bidirectionnelle difficile à maintenir
   - Heureusement supprimé en V4

3. **Tests essentiels**
   - Sans tests approfondis, le bug du trigger serait passé inaperçu

### Recommandations pour un projet réel

1. **Tests automatisés**
   - Créer une suite de tests pour valider chaque migration
   - Tester tous les scénarios (INSERT/UPDATE/DELETE)

2. **Monitoring**
   - Surveiller les métriques après chaque migration
   - Détecter rapidement les anomalies

3. **Documentation**
   - Documenter la stratégie de migration
   - Communiquer avec les équipes

4. **Staging**
   - Tester sur un environnement de staging identique
   - Valider avec des données de production

---

## 15. État final du projet

### Migrations appliquées (TOUTES)

```
V1     - init_schema              : Création de la table bookings (version initiale)
V1.1   - seed_data                : Insertion des données de test
V2     - expand_bookings          : Ajout des nouvelles colonnes
V3     - backfill_full_name       : Migration des données et trigger
V3.1   - fix_trigger_update       : Correction du trigger
V4     - contract_drop_old_columns: Suppression des anciennes colonnes (FINALE)
```

### Données finales

8 réservations dans la base :
1. Jean-Pierre Dupond (CONFIRMED)
2. Marie Leblanc (PENDING)
3. Pierre Durand (CONFIRMED)
4. Sophie Bernard (CANCELLED)
5. Luc Petit (CONFIRMED)
6. Alice Dubois (PENDING)
7. Bob Martin (CONFIRMED)
8. Claire Dupuis (CONFIRMED) - Insérée après V4

### Schéma final

- Table `bookings` : 9 colonnes, 4 index, 2 contraintes (PK + FK)
- Table `booking_status_ref` : 2 colonnes, 3 statuts
- Aucun trigger
- Modèle cohérent et normalisé

---

## 16. Conclusion de l'étape V4

La migration V4 a été appliquée avec succès. Le pattern expand-contract est maintenant complet :

**Objectifs atteints :**
- Modèle de données modernisé
- Intégrité garantie par les contraintes
- Performance optimisée (moins de colonnes, index pertinents)
- Code applicatif simplifié (plus de synchronisation manuelle)

**Risques éliminés :**
- Plus de données incohérentes entre `first_name`/`last_name` et `full_name`
- Plus de statuts invalides grâce à la FK
- Plus de complexité liée au trigger

**Migration réussie sans interruption de service !**

Le projet GlobeTrotter peut maintenant évoluer sereinement avec un modèle de données robuste et évolutif.
