CREATE TABLE IF NOT EXISTS page_contents (
  id INT PRIMARY KEY AUTO_INCREMENT,
  title VARCHAR(255) NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO page_contents (title, body)
VALUES (
  'AWS VPC Local Lab',
  'This HTML content was loaded from the private RDS-style MySQL database.'
);
