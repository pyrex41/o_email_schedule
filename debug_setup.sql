CREATE TABLE contacts (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL,
    birth_date TEXT,
    effective_date TEXT,
    state TEXT,
    zip_code TEXT,
    current_carrier TEXT
);

INSERT INTO contacts (id, email, state, birth_date) VALUES
    (1, 'test1@test.com', 'TX', '1950-03-15'),
    (2, 'test2@test.com', 'CA', '1955-08-20');