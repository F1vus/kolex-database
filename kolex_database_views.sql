-- ============================================================
-- WIDOKI LOGICZNE
-- ============================================================

-- 1. Rozkład jazdy
CREATE OR REPLACE VIEW backend.v_travel_schedule 
AS SELECT
	t.travel_id,
	t.travel_train,
	t.travel_departure,
	tr.travel_stop_number,
	s.station_name,
	s.station_city,
	tr.travel_distance AS distance_from_start_km,
	tr.travel_price AS price_from_start,
	-- godzina przyjazdu = departure podróży + offset przyjazdu
	CASE
		WHEN tr.arrival_offset IS NOT NULL
		THEN t.travel_departure + tr.arrival_offset
		ELSE t.travel_departure
	END AS scheduled_arrival,
	-- godzina odjazdu = departure podróży + offset odjazdu
	CASE
		WHEN tr.departure_offset IS NOT NULL
		THEN t.travel_departure + tr.departure_offset
		ELSE t.travel_departure
	END AS scheduled_departure
FROM backend.travel t
JOIN backend.travel_route tr 
	ON tr.travel_id = t.travel_id
JOIN backend.station s 
	ON s.station_id = tr.travel_station_stop_id
ORDER BY t.travel_id, tr.travel_stop_number;

COMMENT ON VIEW backend.v_travel_schedule 
	IS 'Rozkład jazdy wszystkich podróży wraz z godzinami przyjazdu i odjazdu wyliczanymi na podstawie offsetów trasy';

-- 2. Szczegóły biletów
CREATE OR REPLACE VIEW backend.v_ticket_details 
AS SELECT
	tk.ticket_id,
	tk.ticket_status,
	tk.ticket_price,
	tk.departure_date,
	tk.ticket_created_at,
	-- dane pasażera
	p.profile_id,
	p.profile_first_name,
	p.profile_last_name,
	u.user_email,
	-- pociąg
	tv.travel_id,
	tv.travel_train,
	-- stacja startowa
	s_start.station_name AS departure_station,
	s_start.station_city AS departure_city,
	-- stacja końcowa
	s_end.station_name AS arrival_station,
	s_end.station_city AS arrival_city,
	-- numer miejsca
	se.seat_number,
	tk.start_stop_number,
	tk.end_stop_number
FROM backend.ticket tk
JOIN backend.profile p 
	ON p.profile_id = tk.profile_id
JOIN backend."user" u 
	ON u.user_id = p.user_id
JOIN backend.travel tv 
	ON tv.travel_id = tk.travel_id
JOIN backend.travel_route tr_start 
	ON tr_start.travel_id = tk.travel_id
AND tr_start.travel_stop_number = tk.start_stop_number
JOIN backend.station s_start 
	ON s_start.station_id = tr_start.travel_station_stop_id
JOIN backend.travel_route tr_end 
	ON tr_end.travel_id = tk.travel_id
	AND tr_end.travel_stop_number = tk.end_stop_number
JOIN backend.station s_end 
	ON s_end.station_id = tr_end.travel_station_stop_id
LEFT JOIN backend.seat se 
	ON se.seat_id = tk.seat_id;

COMMENT ON VIEW backend.v_ticket_details 
	IS 'Szczegółowe informacje o biletach, pasażerach, stacjach, podróżach oraz przypisanych miejscach siedzących.';

-- 3. Aktywne rezerwacje
CREATE OR REPLACE VIEW backend.v_active_reservations AS
SELECT
	sr.reservation_id,
	sr.status,
	sr.created_at,
	sr.expires_at,
	-- ile czasu pozostało do wygaśnięcia
	sr.expires_at-NOW() AS time_remaining,
	sr.start_stop_number,
	sr.end_stop_number,
	-- pasażer
	p.profile_id,
	p.profile_first_name,
	p.profile_last_name,
	-- miejsce i podróż
	se.seat_id,
	se.seat_number,
	tv.travel_id,
	tv.travel_train,
	tv.travel_departure,
	-- stacja startowa
	s_start.station_name AS from_station,
	s_start.station_city AS from_city,
	-- stacja docelowa
	s_end.station_name AS to_station,
	s_end.station_city AS to_city
FROM backend.seat_reservation sr
JOIN backend.profile p 
	ON p.profile_id = sr.profile_id
JOIN backend.seat se 
	ON se.seat_id = sr.seat_id
JOIN backend.travel tv 	
	ON tv.travel_id = se.travel_id
JOIN backend.travel_route tr_start 
	ON tr_start.travel_id = se.travel_id
	AND tr_start.travel_stop_number = sr.start_stop_number
JOIN backend.station s_start 
	ON s_start.station_id = tr_start.travel_station_stop_id
JOIN backend.travel_route tr_end 
	ON tr_end.travel_id = se.travel_id
	AND tr_end.travel_stop_number = sr.end_stop_number
JOIN backend.station s_end 
	ON s_end.station_id = tr_end.travel_station_stop_id
WHERE sr.status='HELD'
AND sr.expires_at > NOW();

COMMENT ON VIEW backend.v_active_reservations 
	IS 'Aktywne rezerwacje miejsc oczekujące na opłacenie, które jeszcze nie wygasły';

-- 4. Zajętość miejsc
CREATE OR REPLACE VIEW backend.v_seat_occupancy 
AS SELECT
	tv.travel_id,
	tv.travel_train,
	tv.travel_departure,
	se.seat_id,
	se.seat_number,
	-- liczba aktywnych rezerwacji na to miejsce (mogą pokrywać różne odcinki)
	COUNT(sr.reservation_id) FILTER (
		WHERE sr.status='HELD'
		AND sr.expires_at > NOW()
	) AS active_holds,
	COUNT(sr.reservation_id) FILTER (
		WHERE sr.status='PURCHASED'
	) AS purchased_count,
	COUNT(sr.reservation_id) FILTER (
		WHERE sr.status IN ('EXPIRED','CANCELLED')
	) AS released_count
FROM backend.travel tv
JOIN backend.seat se 
	ON se.travel_id = tv.travel_id
LEFT JOIN backend.seat_reservation sr 
	ON sr.seat_id = se.seat_id
GROUP BY
	tv.travel_id,
	tv.travel_train,
	tv.travel_departure,
	se.seat_id,
	se.seat_number
ORDER BY tv.travel_id, se.seat_number;

COMMENT ON VIEW backend.v_seat_occupancy 
	IS 'Zestawienie zajętości miejsc dla każdej podróży z podziałem na rezerwacje aktywne, zakupione i zwolnione';


-- 5. Podsumowanie użytkowników
CREATE OR REPLACE VIEW backend.v_user_summary 
AS SELECT
	u.user_id,
	u.user_email,
	u.user_role,
	u.user_balance,
	u.user_enabled,
	u.user_created_at,
	p.profile_id,
	p.profile_first_name,
	p.profile_last_name,
	-- statystyki biletów
	COUNT(tk.ticket_id) AS total_tickets,
	COUNT(tk.ticket_id) FILTER (
		WHERE tk.ticket_status='PAID'
	) AS paid_tickets,
	COUNT(tk.ticket_id) FILTER (
		WHERE tk.ticket_status='REFUNDED'
	) AS refunded_tickets,
	COALESCE(
		SUM(tk.ticket_price) FILTER (
			WHERE tk.ticket_status='PAID'
		), 0
	) AS total_spent
FROM backend."user" u
JOIN backend.profile p 
	ON p.user_id = u.user_id
LEFT JOIN backend.ticket tk 
	ON tk.profile_id = p.profile_id
GROUP BY
	u.user_id,
	u.user_email,
	u.user_role,
	u.user_balance,
	u.user_enabled,
	u.user_created_at,
	p.profile_id,
	p.profile_first_name,
	p.profile_last_name;

COMMENT ON VIEW backend.v_user_summary 
	IS 'Podsumowanie użytkowników zawierające dane konta, liczbę biletów oraz łączną wartość zakupów';



-- ============================================================
--  WIDOKI FIZYCZNE
-- ============================================================

-- 6. Przychody z każdej podróży
CREATE MATERIALIZED VIEW backend.mv_travel_revenue 
AS SELECT
    tv.travel_id,
    tv.travel_train,
    tv.travel_departure,
    COUNT(tk.ticket_id) AS tickets_sold,
    SUM(tk.ticket_price) AS total_revenue,
    AVG(tk.ticket_price) AS avg_ticket_price,
    MIN(tk.ticket_price) AS min_ticket_price,
    MAX(tk.ticket_price) AS max_ticket_price
FROM backend.travel tv
LEFT JOIN backend.ticket tk
	ON tk.travel_id = tv.travel_id
    AND tk.ticket_status = 'PAID'
GROUP BY tv.travel_id, tv.travel_train, tv.travel_departure
ORDER BY tv.travel_departure DESC
WITH DATA;

-- Indeks przyspieszający filtrowanie po dacie odjazdu
CREATE INDEX idx_mv_travel_revenue_departure
    ON backend.mv_travel_revenue (travel_departure);

COMMENT ON MATERIALIZED VIEW backend.mv_travel_revenue 
IS 'Statystyki przychodów z podróży obejmujące liczbę sprzedanych biletów oraz średnie ceny';


-- 7. Najpopularniejsze połączenia
CREATE MATERIALIZED VIEW backend.mv_popular_connections 
AS SELECT
	s_start.station_name AS from_station,
    s_start.station_city AS from_city,
    s_end.station_name AS to_station,
    s_end.station_city AS to_city,
    COUNT(tk.ticket_id) AS tickets_sold,
    AVG(tk.ticket_price) AS avg_price,
    MIN(tk.departure_date) AS first_departure,
    MAX(tk.departure_date) AS last_departure
FROM backend.ticket tk
JOIN backend.travel_route tr_start 
	ON tr_start.travel_id = tk.travel_id
    AND tr_start.travel_stop_number = tk.start_stop_number
JOIN backend.station s_start  
	ON s_start.station_id = tr_start.travel_station_stop_id
JOIN backend.travel_route tr_end
	ON tr_end.travel_id = tk.travel_id
    AND tr_end.travel_stop_number = tk.end_stop_number
JOIN backend.station s_end 
	ON s_end.station_id = tr_end.travel_station_stop_id
WHERE tk.ticket_status = 'PAID'
GROUP BY 
	s_start.station_name, 
	s_start.station_city,
    s_end.station_name, 
	s_end.station_city
ORDER BY tickets_sold DESC
WITH DATA;

CREATE INDEX idx_mv_popular_connections_from
    ON backend.mv_popular_connections (from_station, from_city);

COMMENT ON MATERIALIZED VIEW backend.mv_popular_connections 
IS 'Ranking najpopularniejszych połączeń pomiędzy stacjami na podstawie liczby sprzedanych biletów';


-- Miesięczne statystyki sprzedaży
CREATE MATERIALIZED VIEW backend.mv_monthly_sales_stats AS
SELECT
    DATE_TRUNC('month', tk.ticket_created_at) AS sale_month,
    COUNT(tk.ticket_id) AS total_tickets,
    COUNT(tk.ticket_id) FILTER (
			WHERE tk.ticket_status = 'PAID'
		) AS paid_tickets,
    COUNT(tk.ticket_id) FILTER (
			WHERE tk.ticket_status = 'REFUNDED'
		) AS refunded_tickets,
    SUM(tk.ticket_price) FILTER (
			WHERE tk.ticket_status = 'PAID'
		) AS revenue,
    SUM(tk.ticket_price) FILTER (
		WHERE tk.ticket_status = 'REFUNDED'
	) AS refunded_amount,
    COUNT(DISTINCT tk.profile_id) AS unique_passengers,
    AVG(tk.ticket_price) FILTER (
		WHERE tk.ticket_status = 'PAID'
	) AS avg_ticket_price
FROM backend.ticket tk
GROUP BY DATE_TRUNC('month', tk.ticket_created_at)
ORDER BY sale_month DESC
WITH DATA;

CREATE INDEX idx_mv_monthly_sales_month
    ON backend.mv_monthly_sales_stats (sale_month);

COMMENT ON MATERIALIZED VIEW backend.mv_monthly_sales_stats 
	IS 'Miesięczne statystyki sprzedaży biletów, przychodów, zwrotów oraz liczby pasażerów'




	