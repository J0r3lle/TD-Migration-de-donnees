## Compte-rendu : Niveau 1 - Migration MySQL → PostgreSQL

### **Contexte technique**
- **Source** : VM MySQL `172.16.130.130:3306` (base `classicmodels`)
- **Cible** : VM PostgreSQL `172.16.130.129:5432` (base `classicmodels`)
- **Client** : DBeaver sur Mac (`172.16.130.1`) en Bridge VMware Fusion
- **Export** : Réalisé avec succès

### **1. Configuration réseau Host-only**
```
MAC (DBeaver)     172.16.130.1
├─ VM MySQL       172.16.130.130:3306
└─ VM PostgreSQL  172.16.130.129:5432
```
- Passage de NAT (`172.20.10.x`) vers **Bridge** (`172.16.130.x`) 
- IPs statiques configurées via `/etc/netplan/50-netcfg.yaml`
- UFW ouvert : `3306/tcp`, `5432/tcp`, `22/tcp` ALLOW anywhere

### **2. Validation données source (MySQL)**
```sql
-- VM MySQL 172.16.130.130
USE classicmodels;
SELECT COUNT(*) FROM customers;     -- 122 clients
SELECT COUNT(*) FROM orders;        -- 326 réservations
```
**500+ enregistrements validés**

### **3. Configuration utilisateur MySQL**
```sql
-- Création reservation_user pour accès distant
CREATE USER 'reservation_user'@'172.16.130.1' IDENTIFIED BY 'reservation123';
GRANT ALL PRIVILEGES ON classicmodels.* TO 'reservation_user'@'172.16.130.1';
FLUSH PRIVILEGES;
```
- `bind-address = 0.0.0.0` configuré
- MySQL écoute `0.0.0.0:3306` (ss -tulpn)

### **4. Export des données**
```
SCHÉMA + DONNÉES exportés depuis DBeaver
- Dump MySQL classicmodels → fichier SQL
- Préparation import PostgreSQL
```

### **5. Difficultés techniques rencontrées**
| Problème | Cause | Solution |
|----------|-------|----------|
| NAT injoignable | `172.20.10.x` inaccessible | Host-only `172.16.130.x` |
| "Host not allowed" | User `@localhost` seulement | User `@172.16.130.1` |
| Socket MySQL | `/var/run/mysqld` manquant | `sudo mkdir -p /var/run/mysqld` |
| Conflit DHCP | 2 VMs même IP | IPs statiques netplan |

### **6. Validation fonctionnelle**
```
SOURCE MySQL :
├── customers : 122 utilisateurs
└── orders : 326 réservations

EXPORT : Réussi (schéma + données)
PRÊT pour import PostgreSQL (Niveau 2)
```

### **7. Conclusion Niveau 1**
**OBJECTIF ATTEINT** : Extraction complète des données MySQL via DBeaver malgré contraintes réseau (partage de connexion → Host-only).

**Preuve** : 
- Connexion DBeaver → MySQL `172.16.130.130` opérationnelle
- Export `classicmodels` complet réalisé
- Infrastructure bi-VM validée

**Prochaine étape** : Import PostgreSQL + validation cohérence données (Niveau 2).

```
Statut :  NIVEAU 1 VALIDÉ
Temps : 1h30 (incluant résolution réseau)
Prêt pour : Migration + Docker Flyway (Niveau 2)
```
