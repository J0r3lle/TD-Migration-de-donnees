# Compte rendu – Niveau 2  
Migration MySQL → PostgreSQL avec Docker et Flyway

## 1. Objectif du niveau 2

L’objectif du niveau 2 est de migrer une base de données vers PostgreSQL en utilisant :
- Docker pour héberger la base PostgreSQL.
- Flyway pour gérer les scripts de migration (structure et données).

Le but est d’automatiser la création de la table `utilisateurs` et l’insertion de 500 utilisateurs de test, puis de vérifier le résultat dans PostgreSQL à l’aide de DBeaver.

---

## 2. Mise en place de l’environnement

### 2.1 Dossier de travail

Création d’un dossier de projet :

- `C:\Users\user\flyway_migration`

Contenu du dossier :

- `sql/` : scripts de migration Flyway.
- `conf/` : fichiers de configuration Flyway (optionnel pour l’exécution finale).
- `pg-data/` : volume de données pour PostgreSQL.
- `docker-compose.yml` : configuration Docker pour le conteneur PostgreSQL.

### 2.2 PostgreSQL dans Docker

Un conteneur PostgreSQL a été lancé avec les paramètres suivants :

- Base de données : `reservation_voyage`
- Utilisateur : `reservation_voyage`
- Mot de passe : `reservation_voyage_password`
- Port exposé sur l’hôte : `5432`

Ce conteneur constitue la base de données cible pour les migrations Flyway.

---

## 3. Scripts de migration Flyway

Deux migrations versionnées ont été créées dans le dossier `sql`.

### 3.1 `V1__Create_table.sql`

**Nom du fichier :** `V1__Create_table.sql`  
**Rôle :** création de la table `utilisateurs` dans le schéma `public`.

Structure de la table :

- `id` : `SERIAL`, clé primaire.
- `nom` : `VARCHAR(100)`, `NOT NULL`.
- `prenom` : `VARCHAR(100)`, `NOT NULL`.
- `email` : `VARCHAR(255)`, `NOT NULL`, `UNIQUE`.
- `mot_de_passe` : `VARCHAR(255)`, `NOT NULL`.
- `date_creation` : `TIMESTAMP`, `DEFAULT NOW()`.

Ce script reproduit la structure de la table d’utilisateurs indiquée dans le sujet MySQL, adaptée à PostgreSQL.

### 3.2 `V2__Insert_data.sql`

**Nom du fichier :** `V2__Insert_data.sql`  
**Rôle :** insertion de données de test dans la table `utilisateurs`.

Principe :

- Utilisation de `generate_series(1, 500)` pour générer 500 lignes.
- Génération de valeurs factices pour chaque utilisateur :

  - `nom` : `Nom1`, `Nom2`, …
  - `prenom` : `Prenom1`, `Prenom2`, …
  - `email` : `user1@example.com`, `user2@example.com`, …
  - `mot_de_passe` : `mdp1`, `mdp2`, …

Ce script permet de peupler automatiquement la table sans écrire 500 INSERT manuels.

---

## 4. Exécution de Flyway avec Docker

Flyway a été exécuté dans un conteneur Docker en montant le dossier `sql/` du projet.

### 4.1 Commande utilisée

Depuis le dossier `C:\Users\user\flyway_migration`, la commande suivante a été lancée :

```powershell
docker run --rm -v "C:\Users\user\flyway_migration\sql:/flyway/sql" flyway/flyway `
  -url=jdbc:postgresql://host.docker.internal:5432/reservation_voyage `
  -user=reservation_voyage `
  -password=reservation_voyage_password `
  -locations=filesystem:/flyway/sql `
  -baselineOnMigrate=true `
  migrate
