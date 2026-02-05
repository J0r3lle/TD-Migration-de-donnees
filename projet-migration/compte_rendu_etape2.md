# TD 3 - Migration par étapes PostgreSQL
## Compte rendu - Étape 2 : Migration V2 (Expand)

**Date :** 5 février 2025  
**Étudiant :** Johan Caruelle  
**Objectif :** Ajouter les nouvelles colonnes sans supprimer les anciennes pour maintenir la compatibilité

---

## 1. Principe de l'étape Expand

L'étape **Expand** consiste à **ajouter les nouvelles colonnes sans supprimer les anciennes**. Cette approche permet de maintenir la compatibilité avec l'ancienne version de l'application pendant la transition.

### Objectifs de V2

1. Ajouter la colonne `customer_full_name` (nullable pour l'instant)
2. Ajouter la colonne `last_modified_at` avec valeur par défaut
3. Créer la table de référence `booking_status_ref`
4. Conserver toutes les colonnes existantes

### Avantages de cette approche

- **Zero downtime** : Aucune interruption de service
- **Compatibilité** : L'application V1 continue de fonctionner
- **Migration progressive** : Permet de déployer l'application V2 graduellement
- **Rollback possible** : On peut revenir en arrière si nécessaire

---

## 2. Migration V2 - Contenu du fichier

**Fichier : flyway/sql/V2__expand_bookings.sql**

```sql
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
```

---

## 3. Application de la migration

### Commande d'exécution

```bash
docker-compose up flyway
```

### Résultat de l'exécution

```
Flyway OSS Edition 10.22.0 by Redgate
Database: jdbc:postgresql://postgres:5432/globetrotter (PostgreSQL 16.11)
Successfully validated 3 migrations (execution time 00:00.017s)
Current version of schema "public": 1.1
Migrating schema "public" to version "2 - expand booking"
Successfully applied 1 migration to schema "public", now at version v2 (execution time 00:00.010s)
```

---

## 4. Vérification de la migration

### Structure de la table bookings après V2

```sql
\d bookings
```

**Résultat :**

```
Table "public.bookings"
       Column        |            Type             | Collation | Nullable |               Default                
---------------------+-----------------------------+-----------+----------+--------------------------------------
 id                  | bigint                      |           | not null | nextval('bookings_id_seq'::regclass)
 customer_first_name | character varying(100)      |           | not null | 
 customer_last_name  | character varying(100)      |           | not null | 
 customer_email      | character varying(255)      |           | not null | 
 destination         | character varying(255)      |           | not null | 
 departure_date      | date                        |           | not null | 
 return_date         | date                        |           | not null | 
 status              | character varying(50)       |           | not null | 
 created_at          | timestamp without time zone |           | not null | CURRENT_TIMESTAMP
 customer_full_name  | character varying(200)      |           |          | 
 last_modified_at    | timestamp without time zone |           | not null | CURRENT_TIMESTAMP
Indexes:
    "bookings_pkey" PRIMARY KEY, btree (id)
    "idx_bookings_departure_date" btree (departure_date)
    "idx_bookings_email" btree (customer_email)
    "idx_bookings_status" btree (status)
    "idx_bookings_full_name" btree (customer_full_name)
```

### Structure de la table booking_status_ref

```sql
\d booking_status_ref
```

**Résultat :**

```
Table "public.booking_status_ref"
 Column |          Type          | Collation | Nullable | Default 
--------+------------------------+-----------+----------+---------
 code   | character varying(50)  |           | not null | 
 label  | character varying(255) |           | not null | 
Indexes:
    "booking_status_ref_pkey" PRIMARY KEY, btree (code)
```

### Contenu de la table booking_status_ref

```sql
SELECT * FROM booking_status_ref;
```

**Résultat :**

```
   code    |         label          
-----------+------------------------
 PENDING   | En attente de paiement
 CONFIRMED | Réservation confirmée
 CANCELLED | Réservation annulée
(3 rows)
```

### État des données dans bookings

```sql
SELECT id, customer_first_name, customer_last_name, customer_full_name FROM bookings LIMIT 5;
```

**Résultat :**

```
 id | customer_first_name | customer_last_name | customer_full_name 
----+---------------------+--------------------+--------------------
  1 | Jean                | Dupont             | 
  2 | Marie               | Martin             | 
  3 | Pierre              | Durand             | 
  4 | Sophie              | Bernard            | 
  5 | Luc                 | Petit              | 
(5 rows)
```

**Observation importante :** La colonne `customer_full_name` est NULL pour toutes les lignes existantes. C'est normal et attendu. Elle sera remplie dans la migration V3.

---

## 5. Analyse de compatibilité

### Application V1 (ancienne version)

**Utilise :**
- `customer_first_name`
- `customer_last_name`
- `status` (texte libre)

**État après V2 :** Fonctionne normalement, car toutes ces colonnes existent toujours.

**Exemple de requête V1 :**
```sql
INSERT INTO bookings (customer_first_name, customer_last_name, customer_email, destination, departure_date, return_date, status)
VALUES ('Alice', 'Dubois', 'alice@email.fr', 'Berlin', '2025-08-01', '2025-08-07', 'PENDING');
```

Cette requête fonctionne car les colonnes anciennes sont toujours présentes.

---

### Application V2 (nouvelle version)

**Peut utiliser :**
- `customer_full_name` (nouvelle colonne)
- `booking_status_ref` (table de référence)
- `last_modified_at` (nouvelle colonne)

**État après V2 :** Peut commencer à lire/écrire les nouvelles colonnes.

**Exemple de requête V2 :**
```sql
INSERT INTO bookings (customer_full_name, customer_email, destination, departure_date, return_date, status, last_modified_at)
VALUES ('Alice Dubois', 'alice@email.fr', 'Berlin', '2025-08-01', '2025-08-07', 'PENDING', CURRENT_TIMESTAMP);
```

**Note :** L'application V2 peut coexister avec V1 pendant la transition.

---

## 6. Points techniques importants

### Pourquoi customer_full_name est nullable ?

La colonne `customer_full_name` est nullable car :
- Les données existantes n'ont pas encore cette valeur
- Elle sera remplie progressivement dans V3 (backfill)
- Permet d'éviter une erreur lors de l'ajout de la colonne

### Pourquoi on garde la colonne status ?

La colonne `status` est conservée pour :
- Maintenir la compatibilité avec l'application V1
- Éviter une rupture de service
- Permettre une migration progressive

Elle sera supprimée uniquement dans V4, une fois que l'application V1 sera retirée.

### Index créés

Un index a été créé sur `customer_full_name` pour optimiser les futures recherches :
```sql
CREATE INDEX idx_bookings_full_name ON bookings(customer_full_name);
```

### Commentaires de documentation

Des commentaires ont été ajoutés pour documenter l'intention :
```sql
COMMENT ON COLUMN bookings.status IS 
'Colonne legacy. Sera remplacée par une référence à booking_status_ref.code dans V4';
```

Cela aide les développeurs à comprendre le plan de migration.

---

## 7. Schéma de compatibilité

| Colonne               | V1 (avant V2) | Après V2 | V1 compatible ? | V2 compatible ? |
|-----------------------|---------------|----------|-----------------|-----------------|
| id                    | Existe        | Existe   | Oui             | Oui             |
| customer_first_name   | Existe        | Existe   | Oui             | Oui             |
| customer_last_name    | Existe        | Existe   | Oui             | Oui             |
| customer_email        | Existe        | Existe   | Oui             | Oui             |
| destination           | Existe        | Existe   | Oui             | Oui             |
| departure_date        | Existe        | Existe   | Oui             | Oui             |
| return_date           | Existe        | Existe   | Oui             | Oui             |
| status                | Existe        | Existe   | Oui             | Oui             |
| created_at            | Existe        | Existe   | Oui             | Oui             |
| **customer_full_name**| -             | **Ajouté** | Ignoré        | **Utilisé**     |
| **last_modified_at**  | -             | **Ajouté** | Ignoré        | **Utilisé**     |

**Table booking_status_ref** : Nouvelle table, utilisée uniquement par l'application V2.

---

## 8. Stratégie de déploiement

Après la migration V2, plusieurs stratégies de déploiement sont possibles :

### Blue-Green Deployment
1. L'environnement "Blue" (V1) continue de tourner
2. L'environnement "Green" (V2) est déployé en parallèle
3. Le trafic est basculé progressivement vers Green
4. Blue reste disponible pour un rollback rapide

### Rolling Deployment
1. Certains serveurs utilisent V1, d'autres V2
2. Les serveurs sont mis à jour progressivement
3. Si un problème survient, on peut arrêter le rollout

### Canary Deployment
1. V2 est déployé sur un petit pourcentage d'utilisateurs
2. On surveille les métriques et erreurs
3. Si tout va bien, on augmente progressivement le pourcentage

**Point clé :** Toutes ces stratégies fonctionnent car le schéma est compatible avec V1 et V2 simultanément.

---

## 9. Risques évités par le pattern Expand-Contract

### Si on avait fait tout en une seule migration

**Migration monolithique (DANGEREUSE) :**
```sql
-- MAUVAISE APPROCHE - Ne pas faire ça en production !
ALTER TABLE bookings DROP COLUMN customer_first_name;
ALTER TABLE bookings DROP COLUMN customer_last_name;
ALTER TABLE bookings ADD COLUMN customer_full_name VARCHAR(200) NOT NULL;
ALTER TABLE bookings DROP COLUMN status;
ALTER TABLE bookings ADD COLUMN status_code VARCHAR(50) REFERENCES booking_status_ref(code);
```

**Conséquences :**
- Rupture immédiate de l'application V1
- Impossible de faire un rollback propre
- Downtime obligatoire
- Migration de données complexe en une seule étape
- Risque élevé d'erreur

### Avec le pattern Expand-Contract

**Avantages :**
- Aucune rupture de service
- Rollback facile à chaque étape
- Tests progressifs possibles
- Détection précoce des problèmes
- Migration de données contrôlée

---

## 10. État actuel et prochaines étapes

### Migrations appliquées

```
V1   - init_schema       : Création de la table bookings (version initiale)
V1.1 - seed_data         : Insertion des données de test
V2   - expand_bookings   : Ajout des nouvelles colonnes (ACTUELLE)
```

### Schéma actuel

- Table `bookings` avec **anciennes ET nouvelles colonnes**
- Table `booking_status_ref` avec 3 statuts de référence
- 5 index sur la table bookings
- Commentaires de documentation

### Données actuelles

- 5 réservations de test
- `customer_full_name` NULL pour toutes les lignes (sera rempli dans V3)
- Toutes les anciennes colonnes intactes

---

## 11. Prochaine étape : V3 (Transition/Backfill)

La migration V3 devra :

1. **Remplir customer_full_name** pour toutes les lignes existantes
   ```sql
   UPDATE bookings
   SET customer_full_name = customer_first_name || ' ' || customer_last_name;
   ```

2. **Créer un trigger** pour maintenir la cohérence
   - Quand on INSERT/UPDATE avec first_name/last_name → met à jour full_name
   - Quand on INSERT/UPDATE avec full_name → optionnellement met à jour first_name/last_name

3. **Valider les données status** pour qu'elles correspondent aux codes de `booking_status_ref`

Après V3, les deux versions de l'application pourront coexister en production avec une cohérence totale des données.

---

## 12. Commandes de vérification utiles

### Vérifier l'historique des migrations
```sql
SELECT * FROM flyway_schema_history ORDER BY installed_rank;
```

### Vérifier les commentaires sur les colonnes
```sql
SELECT 
    col_description('bookings'::regclass, ordinal_position) as comment,
    column_name
FROM information_schema.columns 
WHERE table_name = 'bookings' 
AND col_description('bookings'::regclass, ordinal_position) IS NOT NULL;
```

### Vérifier les index
```sql
SELECT indexname, indexdef 
FROM pg_indexes 
WHERE tablename = 'bookings';
```

---

## 13. Conclusion de l'étape V2

La migration V2 a été appliquée avec succès. Le schéma est maintenant dans un état intermédiaire qui permet :

- La coexistence de l'application V1 et V2
- Une migration progressive sans interruption de service
- Des tests en production avec un risque minimal
- Un rollback simple si nécessaire

La prochaine étape (V3) consistera à migrer les données existantes vers les nouvelles colonnes et à mettre en place des mécanismes de synchronisation automatique.
