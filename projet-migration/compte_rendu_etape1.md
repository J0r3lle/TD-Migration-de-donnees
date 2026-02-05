# TD 3 - Migration par étapes PostgreSQL
## Compte rendu - Étape 1 : Mise en place du projet

**Date :** 5 février 2025  
**Étudiant :** Johan Caruelle  
**Objectif :** Mise en place de l'environnement Docker avec PostgreSQL et Flyway

---

## 1. Structure du projet

```
projet-migration/
├── docker-compose.yml
└── flyway/
    ├── conf/
    │   └── flyway.conf
    └── sql/
        ├── V1__init_schema.sql
        └── V1_1__seed_data.sql
```

---

## 2. Configuration Docker Compose

**Fichier : docker-compose.yml**

```yaml
version: '3.9'

services:
  postgres:
    image: postgres:16
    container_name: gt_pg_migration
    environment:
      POSTGRES_USER: gt_user
      POSTGRES_PASSWORD: gt_pass
      POSTGRES_DB: globetrotter
    ports:
      - "5434:5432"
    volumes:
      - pgm_data:/var/lib/postgresql/data

  flyway:
    image: flyway/flyway:10
    container_name: gt_pg_flyway
    depends_on:
      - postgres
    volumes:
      - ./flyway/sql:/flyway/sql
      - ./flyway/conf:/flyway/conf
    working_dir: /flyway
    command: [
      "-configFiles=/flyway/conf/flyway.conf",
      "migrate"
    ]

volumes:
  pgm_data:
```

---

## 3. Configuration Flyway

**Fichier : flyway/conf/flyway.conf**

```
flyway.url=jdbc:postgresql://postgres:5432/globetrotter
flyway.user=gt_user
flyway.password=gt_pass
flyway.locations=filesystem:/flyway/sql
flyway.schemas=public
```

---

## 4. Migration V1 - Schéma initial

**Fichier : flyway/sql/V1__init_schema.sql**

```sql
-- Migration V1 : Création du schéma initial
-- Table bookings avec l'ancien modèle

CREATE TABLE bookings (
    id BIGSERIAL PRIMARY KEY,
    customer_first_name VARCHAR(100) NOT NULL,
    customer_last_name VARCHAR(100) NOT NULL,
    customer_email VARCHAR(255) NOT NULL,
    destination VARCHAR(255) NOT NULL,
    departure_date DATE NOT NULL,
    return_date DATE NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index pour améliorer les performances
CREATE INDEX idx_bookings_email ON bookings(customer_email);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_bookings_departure_date ON bookings(departure_date);
```

---

## 5. Migration V1.1 - Données de test

**Fichier : flyway/sql/V1_1__seed_data.sql**

```sql
-- Migration V1.1 : Insertion de données de test

INSERT INTO bookings (
    customer_first_name, 
    customer_last_name, 
    customer_email, 
    destination, 
    departure_date, 
    return_date, 
    status
) VALUES
    ('Jean', 'Dupont', 'jean.dupont@email.fr', 'Paris', '2025-03-15', '2025-03-20', 'CONFIRMED'),
    ('Marie', 'Martin', 'marie.martin@email.fr', 'Tokyo', '2025-04-10', '2025-04-25', 'PENDING'),
    ('Pierre', 'Durand', 'pierre.durand@email.fr', 'New York', '2025-05-01', '2025-05-10', 'CONFIRMED'),
    ('Sophie', 'Bernard', 'sophie.bernard@email.fr', 'Londres', '2025-06-15', '2025-06-20', 'CANCELLED'),
    ('Luc', 'Petit', 'luc.petit@email.fr', 'Rome', '2025-07-01', '2025-07-15', 'CONFIRMED');
```

---

## 6. Problèmes rencontrés et solutions

### Problème 1 : Conteneur Flyway échoue au démarrage

**Erreur :**
```
ERROR: Unable to obtain connection from database (jdbc:postgresql://postgres:5432/globetrotter)
Connection to postgres:5432 refused.
```

**Cause :** Le conteneur Flyway démarre trop rapidement, avant que PostgreSQL ne soit complètement initialisé.

**Solution :** Relancer manuellement Flyway après le démarrage de PostgreSQL :
```bash
docker-compose up flyway
```

**Amélioration possible :** Ajouter un healthcheck dans docker-compose.yml pour que Flyway attende que PostgreSQL soit prêt.

---

### Problème 2 : Conflit de version Flyway

**Erreur :**
```
ERROR: Found more than one migration with version 1
Offenders:
-> /flyway/sql/V1__init_schema.sql (SQL)
-> /flyway/sql/V1__init_seed_data.sql (SQL)
```

**Cause :** Deux fichiers avec la même version V1.

**Solution :** Renommer le fichier de données en `V1_1__seed_data.sql` pour respecter la convention de versioning Flyway.

---

### Problème 3 : Erreur de nommage des fichiers

**Tentatives incorrectes :**
- `V1__init_seed_data.sql` (même version que V1)
- `V1_init_seed_data.sql` (un seul underscore)
- `V1_init__seed_data.sql` (texte au lieu de numéro)

**Nom correct :** `V1_1__seed_data.sql`

**Convention Flyway :**
- Format : `V{version}__{description}.sql`
- Double underscore obligatoire entre version et description
- Exemples valides : `V1__init.sql`, `V1_1__seed.sql`, `V2__expand.sql`

---

## 7. Commandes utilisées

### Lancement de l'environnement
```bash
docker-compose up -d
```

### Vérification des conteneurs
```bash
docker ps
```

### Consultation des logs Flyway
```bash
docker logs gt_pg_flyway
```

### Relance manuelle de Flyway
```bash
docker-compose up flyway
```

### Connexion à PostgreSQL
```bash
docker exec -it gt_pg_migration psql -U gt_user -d globetrotter
```

### Vérification de la structure
```sql
\d bookings
```

### Vérification des données
```sql
SELECT * FROM bookings;
```

### Vérification de l'historique Flyway
```sql
SELECT * FROM flyway_schema_history;
```

---

## 8. Résultat final

### Structure de la table bookings

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
Indexes:
    "bookings_pkey" PRIMARY KEY, btree (id)
    "idx_bookings_departure_date" btree (departure_date)
    "idx_bookings_email" btree (customer_email)
    "idx_bookings_status" btree (status)
```

### Migrations appliquées

```
Successfully validated 2 migrations
Current version of schema "public": 1
Migrating schema "public" to version "1.1 - seed data"
Successfully applied 1 migration to schema "public", now at version v1.1
```

---

## 9. Points clés à retenir

1. **Convention de nommage Flyway stricte** : `V{version}__{description}.sql` avec double underscore
2. **Versioning** : Utiliser des sous-versions (V1.1, V1.2) pour des modifications mineures
3. **Ordre d'exécution** : Flyway exécute les migrations dans l'ordre des versions
4. **Idempotence** : Une fois appliquée, une migration ne peut pas être rejouée
5. **Healthcheck** : Important pour éviter les problèmes de timing au démarrage

---

## 10. État actuel du projet

- Base de données PostgreSQL opérationnelle (port 5434)
- 2 migrations appliquées avec succès (V1 et V1.1)
- Table bookings créée avec 5 enregistrements de test
- Environnement prêt pour les migrations suivantes (V2, V3, V4)

---

## 11. Prochaine étape

**Migration V2 - Étape "Expand"** : Ajout des nouvelles colonnes sans suppression des anciennes pour maintenir la compatibilité avec l'ancienne version de l'application.
