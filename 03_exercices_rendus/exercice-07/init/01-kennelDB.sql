-- Initialisation kennelDB (exercice 07)
CREATE DATABASE IF NOT EXISTS kennelDB
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE kennelDB;

CREATE TABLE clients (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nom VARCHAR(100) NOT NULL,
  prenom VARCHAR(100) NOT NULL,
  date_naissance DATE NOT NULL,
  pseudonyme VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE adresses (
  id INT AUTO_INCREMENT PRIMARY KEY,
  numero VARCHAR(20) NOT NULL,
  rue VARCHAR(200) NOT NULL,
  code_postal VARCHAR(20) NOT NULL,
  commune VARCHAR(100) NOT NULL
);

CREATE TABLE clients_adresses (
  client_id INT NOT NULL,
  adresse_id INT NOT NULL,
  PRIMARY KEY (client_id, adresse_id),
  FOREIGN KEY (client_id) REFERENCES clients(id),
  FOREIGN KEY (adresse_id) REFERENCES adresses(id)
);

CREATE TABLE chiens (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nom VARCHAR(100) NOT NULL,
  date_naissance DATE NOT NULL,
  race VARCHAR(100) NOT NULL,
  sterilise BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE chats (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nom VARCHAR(100) NOT NULL,
  date_naissance DATE NOT NULL,
  race VARCHAR(100) NOT NULL,
  sterilise BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO clients (nom, prenom, date_naissance, pseudonyme) VALUES
  ('Dupont', 'Alice', '1990-03-12', 'alice_d'),
  ('Martin', 'Bob', '1985-07-22', 'bob_m'),
  ('Bernard', 'Claire', '1995-11-05', 'claire_b');

INSERT INTO adresses (numero, rue, code_postal, commune) VALUES
  ('12', 'Rue des Lilas', '75011', 'Paris'),
  ('4B', 'Avenue Victor Hugo', '69002', 'Lyon'),
  ('28', 'Boulevard de la Mer', '13008', 'Marseille');

INSERT INTO clients_adresses (client_id, adresse_id) VALUES
  (1, 1),
  (2, 2),
  (3, 3),
  (1, 2);

INSERT INTO chiens (nom, date_naissance, race, sterilise) VALUES
  ('Rex', '2019-04-01', 'Berger Allemand', TRUE),
  ('Bella', '2021-09-15', 'Labrador', FALSE),
  ('Max', '2018-01-20', 'Beagle', TRUE);

INSERT INTO chats (nom, date_naissance, race, sterilise) VALUES
  ('Minou', '2020-06-10', 'Siamois', TRUE),
  ('Luna', '2022-02-28', 'Maine Coon', FALSE),
  ('Nala', '2017-12-03', 'Persan', TRUE);
