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