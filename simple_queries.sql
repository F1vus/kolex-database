-- QUERY_A1 - bilety z użytkownikami
CREATE OR REPLACE VIEW backend.query_A1 AS
SELECT
    t.ticket_id,
    u.user_email,
    p.profile_first_name,
    p.profile_last_name,
    t.departure_date,
    t.ticket_price,
    t.ticket_status
FROM backend.ticket t
         JOIN backend.profile p ON t.profile_id = p.profile_id
         JOIN backend.user u ON p.user_id = u.user_id;

COMMENT ON VIEW backend.query_A1 IS
'Lista biletów wraz z danymi użytkownika.';


-- QUERY_A2 - aktywne rezerwacje
CREATE OR REPLACE VIEW backend.query_A2 AS
SELECT
    reservation_id,
    seat_id,
    profile_id,
    status,
    created_at,
    expires_at
FROM backend.seat_reservation
WHERE status IN ('HELD', 'PURCHASED');

-- QUERY_A3 - podróże
CREATE OR REPLACE VIEW backend.query_A3 AS
SELECT
    travel_id,
    travel_train,
    travel_departure,
    travel_duration
FROM backend.travel;

COMMENT ON VIEW backend.query_A3 IS
'Lista podróży i pociągów.';


-- QUERY_A4 - trasy i stacje
CREATE OR REPLACE VIEW backend.query_A4 AS
SELECT
    tr.travel_id,
    s.station_name,
    s.station_city,
    tr.travel_stop_number,
    tr.travel_distance,
    tr.travel_price
FROM backend.travel_route tr
         JOIN backend.station s ON tr.travel_station_stop_id = s.station_id;

COMMENT ON VIEW backend.query_A4 IS
'Trasy podróży wraz ze stacjami.';


-- QUERY_A5 - statystyka sprzedaży
CREATE OR REPLACE VIEW backend.query_A5 AS
SELECT
    COUNT(*) AS total_tickets,
    SUM(ticket_price) AS total_revenue
FROM backend.ticket;

COMMENT ON VIEW backend.query_A5 IS
'Statystyka sprzedaży biletów.';


-- QUERY_A6 - użytkownicy
CREATE OR REPLACE VIEW backend.query_A6 AS
SELECT
    user_id,
    user_email,
    user_balance,
    user_role
FROM backend.user;

COMMENT ON VIEW backend.query_A6 IS
'Dane użytkowników i saldo kont.';