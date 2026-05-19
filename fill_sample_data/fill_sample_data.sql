TRUNCATE backend.travel CASCADE;
TRUNCATE backend.travel_route CASCADE;
TRUNCATE backend.seat CASCADE;

CREATE EXTENSION IF NOT EXISTS pgcrypto;


-----------------------------------------------------------
CREATE OR REPLACE FUNCTION backend.fill_sample_data()
RETURNS boolean
LANGUAGE plpgsql
AS
$$
DECLARE
BEGIN
	--fill backned.travel
	INSERT INTO backend.travel (travel_departure, travel_duration, travel_train)
	SELECT
	    NOW() + (gs || ' hours')::interval,
	    (interval '1 hour' + ((random() * 180)::int || ' minutes')::interval),
	    CONCAT((ARRAY['IC 31', 'EIC ', 'EIP '])[1 + floor(random() * 3)::int], gs::text)
	FROM generate_series(1, 250) AS gs;

	--fill backend.travel_route
	WITH selected_stops AS (
	    SELECT
	        t.travel_id,
	        s.station_id,
	        row_number() OVER (PARTITION BY t.travel_id ORDER BY random()) AS stop_no
	    FROM backend.travel t
	    CROSS JOIN LATERAL (
	        SELECT station_id
	        FROM backend.station
	        ORDER BY random()
	        LIMIT 7
	    ) s
	)
	INSERT INTO backend.travel_route (
	    travel_id,
	    travel_station_stop_id,
	    travel_stop_number,
	    travel_distance,
	    travel_price,
	    arrival_offset,
	    departure_offset
	)
	SELECT
	    travel_id,
	    station_id,
	    stop_no,
	    (20 + floor(random() * 480))::int AS travel_distance,
	    round((20 + random() * 200)::numeric, 2) AS travel_price,
	    (stop_no - 1) * interval '15 minutes' AS arrival_offset,
	    (stop_no - 1) * interval '15 minutes' + interval '5 minutes' AS departure_offset
	FROM selected_stops
	ORDER BY travel_id, stop_no;

	-- file backend.seat
	INSERT INTO backend.seat (travel_id, seat_number)
	SELECT
	    t.travel_id,
	    s.seat_number
	FROM backend.travel t
	CROSS JOIN generate_series(1, 92) AS s(seat_number);
   
   RETURN TRUE;
END;
$$;


SELECT backend.fill_sample_data();


-----------------------------------------------------------
CREATE OR REPLACE FUNCTION backend.fill_sample_user_data()
RETURNS boolean
LANGUAGE plpgsql
AS
$$
DECLARE
BEGIN
	--fill backend.user
	INSERT INTO backend.user(user_password, user_email, user_created_at, user_role, user_balance, user_enabled)
	SELECT
    	crypt('password123', gen_salt('bf')),
	    CONCAT('jan_kowalski',gs::text,'@gmail.com'),
	    NOW() + (gs || ' hours')::interval,
		'USER',
		round((random() * 1000)::numeric, 2),
		TRUE
	FROM generate_series(1, 500) AS gs;

	--fill backend.user
	WITH user_profiles AS (
	    SELECT
	        u.user_id,
			(ARRAY['Jan', 'Anna', 'Wałerij'])[1 + floor(random() * 3)::int] AS profile_first_name,
			(ARRAY['Kowalski', 'Nowak', 'Kowal'])[1 + floor(random() * 3)::int] AS profile_last_name
	    FROM backend.user u
		UNION ALL
		SELECT
	        u.user_id,
			(ARRAY['Jan', 'Anna', 'Wałerij'])[1 + floor(random() * 3)::int] AS profile_first_name,
			(ARRAY['Kowalski', 'Nowak', 'Kowal'])[1 + floor(random() * 3)::int] AS profile_last_name
	    FROM backend.user u
		UNION ALL
		SELECT
	        u.user_id,
			(ARRAY['Jan', 'Anna', 'Wałerij'])[1 + floor(random() * 3)::int] AS profile_first_name,
			(ARRAY['Kowalski', 'Nowak', 'Kowal'])[1 + floor(random() * 3)::int] AS profile_last_name
	    FROM backend.user u
	)
	INSERT INTO backend.profile (
	    user_id,
	    profile_first_name,
	    profile_last_name,
	    profile_created_at
	)
	SELECT DISTINCT
	    user_id,
	    profile_first_name,
	    profile_last_name,
	   	NOW() + interval '1 hour' AS profile_created_at
	FROM user_profiles
	ORDER BY user_id;

   RETURN TRUE;
END;
$$;

SELECT backend.fill_sample_user_data();

-----------------------------------------------------------
CREATE OR REPLACE FUNCTION backend.generate_test_tickets()
RETURNS TABLE (
    profile_id BIGINT,
    reservation_id BIGINT,
    ticket_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
v_profile RECORD;
    v_travel_id BIGINT;
    v_seat_id BIGINT;
    v_start_stop INT;
    v_end_stop INT;
    v_max_stop INT;
    v_reservation_id BIGINT;
    v_ticket_id BIGINT;
BEGIN
    FOR v_profile IN
    SELECT p.profile_id, p.user_id
    FROM backend.profile p
    WHERE NOT EXISTS (
        SELECT 1
        FROM backend.ticket t
        WHERE t.profile_id = p.profile_id
    )
    ORDER BY p.profile_id
        LOOP
    SELECT t.travel_id, MAX(tr.travel_stop_number)
    INTO v_travel_id, v_max_stop
    FROM backend.travel t
             JOIN backend.travel_route tr ON tr.travel_id = t.travel_id
    WHERE EXISTS (
        SELECT 1
        FROM backend.seat s
        WHERE s.travel_id = t.travel_id
    )
    GROUP BY t.travel_id
    HAVING COUNT(DISTINCT tr.travel_stop_number) >= 2
    ORDER BY random()
        LIMIT 1;

    IF v_travel_id IS NULL OR v_max_stop IS NULL OR v_max_stop < 2 THEN
                CONTINUE;
    END IF;

    SELECT s.seat_id
    INTO v_seat_id
    FROM backend.seat s
    WHERE s.travel_id = v_travel_id
    ORDER BY random()
        LIMIT 1;

    IF v_seat_id IS NULL THEN
                CONTINUE;
    END IF;

    v_start_stop := 1 + floor(random() * (v_max_stop - 1))::int;
    v_end_stop := v_start_stop + 1 + floor(random() * (v_max_stop - v_start_stop))::int;

    BEGIN
        SELECT r.reservation_id
        INTO v_reservation_id
        FROM backend.reserve_seat(
                     v_seat_id,
                     v_profile.profile_id,
                     v_start_stop,
                     v_end_stop
        ) AS r;

        IF v_reservation_id IS NULL THEN
                        CONTINUE;
        END IF;

        SELECT b.ticket_id
        INTO v_ticket_id
        FROM backend.buy_ticket(
                     v_reservation_id,
                     v_profile.user_id
        ) AS b;

        IF v_ticket_id IS NULL THEN
                        CONTINUE;
        END IF;

        profile_id := v_profile.profile_id;
        reservation_id := v_reservation_id;
        ticket_id := v_ticket_id;
        RETURN NEXT;

    EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Skip profile_id=%, error=%', v_profile.profile_id, SQLERRM;
            CONTINUE;
            END;
            END LOOP;

    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION backend.reserve_seat(
    p_seat_id BIGINT,
    p_profile_id BIGINT,
    p_start_stop INT,
    p_end_stop INT
)
RETURNS TABLE (
    reservation_id BIGINT,
    seat_id BIGINT,
    status VARCHAR,
    created_at TIMESTAMP,
    expires_at TIMESTAMP
)
AS $$
BEGIN
    -- sprawdzenie konfliktu
    IF EXISTS (
        SELECT 1
        FROM backend.seat_reservation sr
        WHERE sr.seat_id = p_seat_id
          AND sr.status = 'HELD'
          AND sr.expires_at > NOW()
    ) THEN
        RAISE EXCEPTION 'Seat is already reserved';
    END IF;

    RETURN QUERY
    INSERT INTO backend.seat_reservation AS sr (
        seat_id,
        profile_id,
        status,
        start_stop_number,
        end_stop_number,
        created_at,
        expires_at
    )
    VALUES (
        p_seat_id,
        p_profile_id,
        'HELD',
        p_start_stop,
        p_end_stop,
        NOW(),
        NOW() + INTERVAL '10 minutes'
    )
    RETURNING
        sr.reservation_id,
        sr.seat_id,
        sr.status,
        sr.created_at,
        sr.expires_at;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION backend.buy_ticket(
    p_reservation_id BIGINT,
    p_user_id BIGINT
)
RETURNS TABLE (
    ticket_id BIGINT,
    message TEXT
)
AS $$
DECLARE
    v_res backend.seat_reservation%ROWTYPE;
    v_user_balance NUMERIC;
    v_total_price NUMERIC;
    v_ticket_id BIGINT;
    v_travel_departure TIMESTAMP;
    v_offset INTERVAL;
BEGIN

    -- =========================================================
    -- 1. LOAD RESERVATION
    -- =========================================================
    SELECT *
    INTO v_res
    FROM backend.seat_reservation sr
    WHERE sr.reservation_id = p_reservation_id
    FOR UPDATE;

    IF v_res IS NULL THEN
        RAISE EXCEPTION 'No reservation found';
    END IF;

    IF v_res.status <> 'HELD' THEN
        RAISE EXCEPTION 'Reservation already processed';
    END IF;

    IF v_res.expires_at < NOW() THEN
        RAISE EXCEPTION 'Reservation expired';
    END IF;

    -- =========================================================
    -- 2. CALCULATE PRICE (simplified equivalent of calculatePrice)
    -- =========================================================
    v_total_price :=
        (v_res.end_stop_number - v_res.start_stop_number) * 10;

    -- =========================================================
    -- 3. CHECK USER BALANCE
    -- =========================================================
    SELECT user_balance
    INTO v_user_balance
    FROM backend."user"
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF v_user_balance IS NULL THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    IF v_user_balance < v_total_price THEN
        RAISE EXCEPTION 'Insufficient funds';
    END IF;

    -- =========================================================
    -- 4. DEDUCT BALANCE
    -- =========================================================
    UPDATE backend."user"
    SET user_balance = user_balance - v_total_price
    WHERE user_id = p_user_id;

    -- =========================================================
    -- 5. GET TRAVEL DATA (departure + offset logic)
    -- =========================================================
    SELECT t.travel_departure
    INTO v_travel_departure
    FROM backend.travel t
    JOIN backend.seat s ON s.travel_id = t.travel_id
    WHERE s.seat_id = v_res.seat_id;

    SELECT tr.departure_offset
    INTO v_offset
    FROM backend.travel_route tr
    WHERE tr.travel_id = (
        SELECT travel_id FROM backend.seat WHERE seat_id = v_res.seat_id
    )
    AND tr.travel_stop_number = v_res.start_stop_number;

    -- =========================================================
    -- 6. CREATE TICKET
    -- =========================================================
    INSERT INTO backend.ticket as t (
        travel_id,
        profile_id,
        ticket_price,
        departure_date,
        start_stop_number,
        end_stop_number,
        ticket_created_at,
        seat_id,
        ticket_status
    )
    VALUES (
        (SELECT travel_id FROM backend.seat WHERE seat_id = v_res.seat_id),
        v_res.profile_id,
        v_total_price,
        v_travel_departure + v_offset,
        v_res.start_stop_number,
        v_res.end_stop_number,
        NOW(),
        v_res.seat_id,
        'PAID'
    )
    RETURNING t.ticket_id INTO v_ticket_id;

    -- =========================================================
    -- 7. FINALIZE RESERVATION
    -- =========================================================
    UPDATE backend.seat_reservation
    SET status = 'PURCHASED',
        ticket_id = v_ticket_id
    WHERE reservation_id = p_reservation_id;

    -- =========================================================
    -- RETURN
    -- =========================================================
    RETURN QUERY
    SELECT v_ticket_id, 'Ticket purchased successfully';

END;
$$ LANGUAGE plpgsql;



SELECT * FROM backend.generate_test_tickets();


