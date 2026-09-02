-- mapping.material_production_line.line_json carries width, height and weight
-- on the root for 303 of its 523 rows; the other 184 already have a specs
-- array. Everything that reads a format reads specs, so the loose keys move
-- into a one-object specs array.
--
-- The height brackets follow the media type:
--   1 sheet — a sheet has one height: min_height = max_height = height
--   3 roll  — a roll is cut to length: min_height 10, max_height 2500
--   other   — no bracket invented; see the note at the bottom
--
-- Rows that already have specs are left alone, so this is re-runnable.

BEGIN;

UPDATE mapping.material_production_line m
SET line_json = (m.line_json - 'width' - 'height' - 'weight')
                || jsonb_build_object('specs', jsonb_build_array(
                       jsonb_strip_nulls(
                           jsonb_build_object(
                               'width',  m.line_json -> 'width',
                               'height', m.line_json -> 'height',
                               'weight', m.line_json -> 'weight')
                           || CASE m.line_json ->> 'material_media_type_id'
                                  WHEN '1' THEN jsonb_build_object(
                                      'min_height', m.line_json -> 'height',
                                      'max_height', m.line_json -> 'height')
                                  WHEN '3' THEN jsonb_build_object(
                                      'min_height', 10,
                                      'max_height', 2500)
                                  ELSE '{}'::jsonb
                              END)))
WHERE jsonb_array_length(coalesce(m.line_json -> 'specs', '[]'::jsonb)) = 0
  AND m.line_json ? 'width';

COMMIT;

-- expected: 303 rows — 93 sheet, 170 roll, 37 piece (media type 2) and 3
-- without a media type. Those last 40 get width, height and weight but no
-- bracket: the waste lookup keys on max_height, so they stay outside it until
-- their media type says what a height means. 36 further rows have no width at
-- all and are untouched.
