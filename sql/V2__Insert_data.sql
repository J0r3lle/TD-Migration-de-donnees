-- V2__Insert_data.sql
INSERT INTO utilisateurs (nom, prenom, email, mot_de_passe)
SELECT
    'Nom' || i        AS nom,
    'Prenom' || i     AS prenom,
    'user' || i || '@example.com' AS email,
    'mdp' || i        AS mot_de_passe
FROM generate_series(1, 500) AS s(i);
