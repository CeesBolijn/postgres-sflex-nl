create function clean_phone_number(str character varying) returns character varying
	language plpgsql
as $$
BEGIN
    IF LENGTH(str) > 1 THEN
        -- Replace '+' with '00' and remove '(0)'
        str := REPLACE(REPLACE(str, '+', '00'), '(0)', '');

        -- Remove all non-numeric characters
        str := REGEXP_REPLACE(str, '[^0-9]', '', 'g');

        -- If second character is not '0', prepend country code
        IF SUBSTRING(str, 2, 1) <> '0' THEN
            str := '0031' || SUBSTRING(str, 2, 9);
        END IF;

        -- Format the number with spaces
        IF LENGTH(str) > 5 THEN
            str := TRIM(CONCAT(
                LEFT(str, 4), ' ',
                SUBSTRING(str, 5, 3), ' ',
                SUBSTRING(str, 8, 3), ' ',
                SUBSTRING(str, 11, 3), ' ',
                SUBSTRING(str, 14, 9)
            ));
        END IF;
    END IF;

    RETURN str;
END;
$$;

alter function clean_phone_number(varchar) owner to xfw3;

