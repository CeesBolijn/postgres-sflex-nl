create function test_get_nesting_preview() returns TABLE(source text, sheet json, items json)
	immutable
	language sql
as $$
  select
    'probo-xml'::text,
    '{"width": 1000, "height": 3000}'::json,
    '[
      {"x":10,  "y":10,  "width":200, "height":300, "rotation":0,  "priority":5, "timeLeft":3, "previewColor":"#4A90D9"},
      {"x":220, "y":10,  "width":150, "height":400, "rotation":0,  "priority":2, "timeLeft":1, "previewColor":"#E67E22"},
      {"x":10,  "y":320, "width":300, "height":200, "rotation":90, "priority":1, "timeLeft":0, "previewColor":"#E74C3C"},
      {"x":380, "y":10,  "width":250, "height":250, "rotation":0,  "priority":4, "timeLeft":5, "previewColor":"#2ECC71"}
    ]'::json
$$;

alter function test_get_nesting_preview() owner to xfw3;

