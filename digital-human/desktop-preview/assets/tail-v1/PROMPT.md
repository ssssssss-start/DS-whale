# Tail root reconstruction

Mode: built-in imagegen, transparent background. Reference: `../emotions-v1/neutral.png`.

Use case: background-extraction. Production 2D animation layer edit. From this exact whale-girl reference, extract ONLY her blue curved whale tail visible on the bottom right, including its two-lobed fluke, and reconstruct the short hidden root extending leftward beneath her skirt. Output a standalone transparent RGBA tail sprite on the SAME full-character portrait canvas, in exactly the original tail location, scale, curvature, colors and clean dark-blue outline. Tail root approximately at normalized canvas (0.58,0.79), curved belly sweeps down to (0.72,0.88), fluke tips near (0.82,0.67) and (0.99,0.67). Keep tail silhouette matching reference precisely. Remove ALL character, hair, clothes, legs, face and other details: only tail remains, empty transparent canvas everywhere else. Extend left root smoothly about 25 pixels behind where skirt/leg would cover it. No white background, no text, no shadows, no redesign, no extra fins.

The generated full tail is preserved as root-source.png. Runtime uses only a small hidden-root patch; the visible tail is separated from the original character texture to preserve its design.
