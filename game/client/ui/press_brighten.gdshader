// Lays white at half opacity over what's drawn while pressed. Only where
// something is drawn: the item button's circle style box in item_button.tscn
// turns off anti-aliasing, so its edge is hard and every drawn pixel is the
// circle's own.
shader_type canvas_item;

uniform bool pressed = false;

const float OVERLAY_ALPHA = 0.5;

void fragment() {
	if (pressed && COLOR.a > 0.0) {
		float alpha = OVERLAY_ALPHA + COLOR.a * (1.0 - OVERLAY_ALPHA);
		COLOR.rgb = (vec3(OVERLAY_ALPHA) + COLOR.rgb * COLOR.a * (1.0 - OVERLAY_ALPHA)) / alpha;
		COLOR.a = alpha;
	}
}
