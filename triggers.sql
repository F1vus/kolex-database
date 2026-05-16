--  TRIGGER 1: Walidacja geograficznej kolejności przystanków
CREATE OR REPLACE FUNCTION backend.fn_validate_ticket()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_exists INT;
    v_end_exists INT;
    v_departure TIMESTAMP;
    v_seat_travel BIGINT;
BEGIN
    -- sprawdzanie czy przystanek startowy istnieje w tej podróży
    SELECT COUNT(*) INTO v_start_exists
    FROM backend.travel_route
    WHERE travel_id = NEW.travel_id
    	AND travel_stop_number = NEW.start_stop_number;
 
    IF v_start_exists = 0 THEN
    	RAISE EXCEPTION
            'Przystanek startowy nr % nie istnieje w podróży %.',
            NEW.start_stop_number, NEW.travel_id;
    END IF;
 
    -- sprawdzanie czy przystanek końcowy istnieje w tej podróży
    SELECT COUNT(*) INTO v_end_exists
    FROM backend.travel_route
    WHERE travel_id = NEW.travel_id
    	AND travel_stop_number = NEW.end_stop_number;
 
    IF v_end_exists = 0 THEN
        RAISE EXCEPTION
            'Przystanek końcowy nr % nie istnieje w podróży %',
            NEW.end_stop_number, NEW.travel_id;
    END IF;
 
    -- sprawdzanie kolejności end_stop_number > start_stop_number
    IF NEW.end_stop_number <= NEW.start_stop_number THEN
        RAISE EXCEPTION
            'Przystanek końcowy (%) musi mieć wyższy numer niż startowy (%)'
            'Sprawdź kierunek trasy przystanki są numerowane w jednym kierunku jazdy',
            NEW.end_stop_number, NEW.start_stop_number;
    END IF;
 
    -- uniemożliwienie zakupu biletu na podróż, która już się odbyła
    SELECT travel_departure INTO v_departure
    FROM backend.travel
    WHERE travel_id = NEW.travel_id;
 
    IF v_departure < NOW() THEN
        RAISE EXCEPTION
            'Nie można wystawić biletu podróż % odbyła się %',
            NEW.travel_id, v_departure;
    END IF;
 
    -- sprawdzenie czy podanie miejsce że należy do tej samej podróży
	IF NEW.seat_id IS NOT NULL THEN
    	SELECT travel_id INTO v_seat_travel
        FROM backend.seat
        WHERE seat_id = NEW.seat_id;
 
        IF v_seat_travel != NEW.travel_id THEN
            RAISE EXCEPTION
                'Miejsce % należy do podróży %, a nie do % niezgodność',
                NEW.seat_id, v_seat_travel, NEW.travel_id;
        END IF;
    END IF;
 
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION backend.fn_validate_ticket() 
	IS 'Funkcja sprawdza istnienie przystanków w danej podróży, poprawność kolejności trasy,
		zgodność miejsca siedzącego z podróżą oraz blokuje zakup biletu na przejazd,
		który już się odbył';
 
CREATE TRIGGER trg_validate_ticket
BEFORE INSERT OR UPDATE ON backend.ticket
FOR EACH ROW
EXECUTE FUNCTION backend.fn_validate_ticket();
 
COMMENT ON TRIGGER trg_validate_ticket ON backend.ticket 
	IS 'Uruchamia fn_validate_ticket() przed każdym INSERT/UPDATE na tabeli ticket.
 		Blokuje logicznie niepoprawne bilety: zły kierunek trasy, nieistniejące
 		przystanki, przeszła data podróży oraz niezgodność miejsca z podróżą';
 

--  TRIGGER 2: Spójność numeracji przystanków trasy (travel_route)
CREATE OR REPLACE FUNCTION backend.fn_validate_route_sequence()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_max_stop INT;
    v_min_stop INT;
    v_count INT;
BEGIN
    -- walidacja numeru nowego przystanku
	IF TG_OP IN ('INSERT', 'UPDATE') THEN
 
        -- przy UPDATE pomijamy własny wiersz w obliczeniach
        SELECT
            COALESCE(MAX(travel_stop_number), 0),
            COUNT(*)
        INTO v_max_stop, v_count
        FROM backend.travel_route
        WHERE travel_id = NEW.travel_id
          AND NOT (TG_OP = 'UPDATE'
                   AND travel_stop_number = OLD.travel_stop_number);
 
        -- pierwsza stacja musi mieć numer 1
        IF v_count = 0 AND NEW.travel_stop_number != 1 THEN
            RAISE EXCEPTION
                'Pierwsza stacja trasy % musi mieć travel_stop_number = 1, podano %.',
                NEW.travel_id, NEW.travel_stop_number;
        END IF;
 
        -- kolejna stacja musi być max + 1
        IF v_count > 0 AND NEW.travel_stop_number != v_max_stop + 1 THEN
            RAISE EXCEPTION
                'Nowy przystanek trasy % musi mieć numer % (max+1), podano %. '
                'Przystanki muszą być numerowane kolejno bez luk.',
                NEW.travel_id, v_max_stop + 1, NEW.travel_stop_number;
        END IF;

 	-- zakaz usuwania środkowego przystanku
    ELSIF TG_OP = 'DELETE' THEN
 
        SELECT MAX(travel_stop_number) INTO v_max_stop
        FROM backend.travel_route
        WHERE travel_id = OLD.travel_id;
 
        -- można usunąć tylko ostatni przystanek
        IF OLD.travel_stop_number != v_max_stop THEN
            RAISE EXCEPTION
                'Nie można usunąć przystanku % trasy % usuwać można tylko ostatni przystanek (nr %).',
                OLD.travel_stop_number, OLD.travel_id, v_max_stop;
        END IF;
 
    END IF;
 
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

COMMENT ON FUNCTION backend.fn_validate_route_sequence() 
	IS 'Funkcja wyzwalacza odpowiedzialna za kontrolę ciągłości numeracji przystanków.
 		Sprawdza poprawność kolejności podczas INSERT i UPDATE oraz blokuje usuwanie
 		przystanków ze środka trasy, aby zachować spójną sekwencję numerów';

CREATE TRIGGER trg_validate_route_sequence
BEFORE INSERT OR UPDATE OR DELETE ON backend.travel_route
FOR EACH ROW
EXECUTE FUNCTION backend.fn_validate_route_sequence();

COMMENT ON TRIGGER trg_validate_route_sequence ON backend.travel_route 
	IS 'Wyzwalacz uruchamiający fn_validate_route_sequence() przed modyfikacją tabeli
 		travel_route. Zapewnia ciągłą numerację przystanków oraz chroni trasę przed
		powstawaniem luk i niespójnej kolejności';


--  TRIGGER 3: Automatyczne wygaszanie przeterminowanych rezerwacji 
CREATE OR REPLACE FUNCTION backend.fn_handle_reservation_expiry()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'HELD' THEN
        IF NEW.expires_at IS NULL THEN
            NEW.expires_at := NOW() + INTERVAL '15 minutes';
            RAISE NOTICE
                'Rezerwacja %: brak expires_at - ustawiono % (NOW+15min)',
                NEW.reservation_id, NEW.expires_at;
        END IF;
 
        IF NEW.expires_at <= NOW() + INTERVAL '1 minute' THEN
            RAISE EXCEPTION
                'expires_at (%) musi być co najmniej 1 minutę w przyszłości',
                NEW.expires_at;
        END IF;
    END IF;
 
    -- sprawdzanie przy zakupie, czy rezerwacja nie wygasła
    IF TG_OP = 'UPDATE'
       AND OLD.status = 'HELD'
       AND NEW.status = 'PURCHASED' THEN
 
        IF OLD.expires_at < NOW() THEN
            -- automatycznie wygaś zamiast zakupu
            NEW.status := 'EXPIRED';
 
            RAISE EXCEPTION
                'Rezerwacja % wygasła o %. Zakup niemożliwy złóż nową rezerwację',
                OLD.reservation_id, OLD.expires_at;
        END IF;
    END IF;
 
    --  blokada zmiany statusu EXPIRED/CANCELLED
    IF TG_OP = 'UPDATE'
       AND OLD.status IN ('EXPIRED', 'CANCELLED')
       AND NEW.status != OLD.status THEN
 
        RAISE EXCEPTION
            'Rezerwacja % ma status % nie można zmienić na %.'
            OLD.reservation_id, OLD.status, NEW.status;
    END IF;
 
    RETURN NEW;
END;
$$;
 
COMMENT ON FUNCTION backend.fn_handle_reservation_expiry() 
	IS 'Funkcja wyzwalacza odpowiedzialna za obsługę czasu ważności rezerwacji.
 		Ustawia domyślne expires_at dla nowych rezerwacji HELD, blokuje zakup
 		wygasłych rezerwacji oraz zabezpiecza statusy EXPIRED i CANCELLED
 		przed ponowną zmianą';
 
CREATE TRIGGER trg_handle_reservation_expiry
BEFORE INSERT OR UPDATE ON backend.seat_reservation
FOR EACH ROW
EXECUTE FUNCTION backend.fn_handle_reservation_expiry();

COMMENT ON TRIGGER trg_handle_reservation_expiry ON backend.seat_reservation 
	IS 'Wyzwalacz uruchamiający fn_handle_reservation_expiry() przed INSERT i UPDATE
 		w tabeli seat_reservation. Kontroluje czas ważności rezerwacji, obsługę
 		wygasłych rezerwacji oraz poprawność zmian statusów';





