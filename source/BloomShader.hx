package;

import flixel.system.FlxAssets.FlxShader;

class BloomShader extends FlxShader // BLOOM SHADER BY BBPANZU
{
	@:glFragmentSource('
	#pragma header

    // GAUSSIAN BLUR SETTINGS
  	uniform float dim;
    uniform float Directions;
    uniform float Quality; 
    uniform float Size; 

	void main(void)
	{ 
		vec2 uv = openfl_TextureCoordv.xy ;

		float Pi = 6.28318530718; // Pi*2

		vec4 Color = texture2D( bitmap, uv);
		
		for (int di = 0; di < 64; di++) {
			if (float(di) >= Directions)
				break;
			float d = float(di) * Pi / Directions;
			for (int qi = 1; qi <= 16; qi++) {
				if (float(qi) > Quality)
					break;
				float i = float(qi) / Quality;

				float ex = (cos(d)*Size*i)/openfl_TextureSize.x;
				float why = (sin(d)*Size*i)/openfl_TextureSize.y;
				Color += flixel_texture2D( bitmap, uv+vec2(ex,why));	
			}
		}
		
		Color /= (dim * Quality) * Directions - 15.0;
		vec4 bloom =  (flixel_texture2D( bitmap, uv)/ dim)+Color;

		gl_FragColor = bloom;

	}
	')
	public function new()
	{
		super();

		Size.value = [18.0];
		Quality.value = [#if mobile 4.0 #else 8.0 #end];
		dim.value = [2.0];
		Directions.value = [16.0];
	}
}
