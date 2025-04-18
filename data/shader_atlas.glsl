//example of some shaders compiled
flat basic.vs flat.fs
texture basic.vs texture.fs
skybox basic.vs skybox.fs
depth quad.vs depth.fs
multi basic.vs multi.fs
singlepass basic.vs singlepass.fs
normalmap basic.vs normalmap.fs
multipass basic.vs multipass.fs
debug basic.vs debug.fs
plain basic.vs plain.fs
compute test.cs

\test.cs
#version 430 core

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void main() 
{
	vec4 i = vec4(0.0);
}

\basic.vs

#version 330 core

in vec3 a_vertex;
in vec3 a_normal;
in vec2 a_coord;
in vec4 a_color;

uniform vec3 u_camera_pos;

uniform mat4 u_model;
uniform mat4 u_viewprojection;

//this will store the color for the pixel shader
out vec3 v_position;
out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_uv;
out vec4 v_color;

uniform float u_time;

void main()
{	
	//calcule the normal in camera space (the NormalMatrix is like ViewMatrix but without traslation)
	v_normal = (u_model * vec4( a_normal, 0.0) ).xyz;
	
	//calcule the vertex in object space
	v_position = a_vertex;
	v_world_position = (u_model * vec4( v_position, 1.0) ).xyz;
	
	//store the color in the varying var to use it from the pixel shader
	v_color = a_color;

	//store the texture coordinates
	v_uv = a_coord;

	//calcule the position of the vertex using the matrices
	gl_Position = u_viewprojection * vec4( v_world_position, 1.0 );
}

\quad.vs

#version 330 core

in vec3 a_vertex;
in vec2 a_coord;
out vec2 v_uv;

void main()
{	
	v_uv = a_coord;
	gl_Position = vec4( a_vertex, 1.0 );
}


\flat.fs

#version 330 core

uniform vec4 u_color;

out vec4 FragColor;

void main()
{
	FragColor = u_color;
}


\texture.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_alpha_cutoff;

out vec4 FragColor;

void main()
{
	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, v_uv );

	if(color.a < u_alpha_cutoff)
		discard;

	FragColor = color;
}


\skybox.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;

uniform samplerCube u_texture;
uniform vec3 u_camera_position;
out vec4 FragColor;

void main()
{
	vec3 E = v_world_position - u_camera_position;
	vec4 color = texture( u_texture, E );
	FragColor = color;
}


\multi.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_alpha_cutoff;

layout(location = 0) out vec4 FragColor;
layout(location = 1) out vec4 NormalColor;

void main()
{
	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, uv );

	if(color.a < u_alpha_cutoff)
		discard;

	vec3 N = normalize(v_normal);

	FragColor = color;
	NormalColor = vec4(N,1.0);
}


\depth.fs

#version 330 core

uniform vec2 u_camera_nearfar;
uniform sampler2D u_texture; //depth map
in vec2 v_uv;
out vec4 FragColor;

void main()
{
	float n = u_camera_nearfar.x;
	float f = u_camera_nearfar.y;
	float z = texture2D(u_texture,v_uv).x;
	if( n == 0.0 && f == 1.0 )
		FragColor = vec4(z);
	else
		FragColor = vec4( n * (z + 1.0) / (f + n - z * (f - n)) );
}


\instanced.vs

#version 330 core

in vec3 a_vertex;
in vec3 a_normal;
in vec2 a_coord;

in mat4 u_model;

uniform vec3 u_camera_pos;

uniform mat4 u_viewprojection;

//this will store the color for the pixel shader
out vec3 v_position;
out vec3 v_world_position;
out vec3 v_normal;
out vec2 v_uv;

void main()
{	
	//calcule the normal in camera space (the NormalMatrix is like ViewMatrix but without traslation)
	v_normal = (u_model * vec4( a_normal, 0.0) ).xyz;
	
	//calcule the vertex in object space
	v_position = a_vertex;
	v_world_position = (u_model * vec4( a_vertex, 1.0) ).xyz;
	
	//store the texture coordinates
	v_uv = a_coord;

	//calcule the position of the vertex using the matrices
	gl_Position = u_viewprojection * vec4( v_world_position, 1.0 );
}

\singlepass.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform sampler2D u_normal_texture;
uniform float u_time;
uniform float u_alpha_cutoff;

uniform vec3 u_light_ambient;

uniform vec3 u_light_pos[10];
uniform vec3 u_light_color[10];
uniform float u_light_int[10];
uniform vec3 u_light_dir[10];
uniform int u_light_count;
uniform int u_light_type[10];
uniform float u_light_min[10];
uniform float u_light_max[10];

uniform float u_light_cone_max[10];	//FOR SPOT LIGHTS
uniform float u_light_cone_min[10];		//FOR SPOT LIGHTS

uniform float u_material_shine;
uniform vec3 u_camera_pos;

out vec4 FragColor;

void main()
{

	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, v_uv );

	vec3 light_component = vec3(0.0, 0.0, 0.0);

	light_component += u_light_ambient * color.rgb;

	for(int i = 0; i < u_light_count; i++){

		if(u_light_type[i] == 1) {										//POINT
			float dist = distance(u_light_pos[i], v_world_position);
			float attenuation = 1.0 / pow(dist, 2);
			vec3 L = normalize(u_light_pos[i] - v_world_position);

			float l_dot_n = clamp(dot(L,normalize(v_normal)), 0.0, 1.0);
			light_component += u_light_int[i] * attenuation * u_light_color[i] * l_dot_n;

			
			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(v_normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int[i] * attenuation * u_light_color[i];


		} else if (u_light_type[i] == 2) {								//SPOT
			float dist = distance(u_light_pos[i], v_world_position);
			float attenuation = 1.0 / pow(dist, 2);
			vec3 L = normalize(u_light_pos[i] - v_world_position);
			vec3 D = normalize(u_light_dir[i]);

			if(dot(L, D) < u_light_cone_max[i]) {	//check if the pixel is within the cone
				continue;
			}

			float cone_factor = (clamp(dot(L, D) , 0.0, 1.0) - (u_light_cone_max[i])) / (u_light_cone_min[i] - u_light_cone_max[i]);

			float spot_intensity = u_light_int[i] * attenuation * cone_factor;

			float l_dot_n = clamp(dot(L,normalize(v_normal)), 0.0, 1.0);
			light_component += spot_intensity * u_light_color[i] * l_dot_n;

			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(v_normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int[i] * attenuation * u_light_color[i];


		} else if (u_light_type[i] == 3) {								//DIRECTIONAL
			vec3 L = normalize(u_light_dir[i]);
			float l_dot_n = clamp(dot(L,normalize(v_normal)), 0, 1);
			light_component += u_light_int[i] * u_light_color[i] * l_dot_n;

			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(v_normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int[i] * u_light_color[i];
		}


		
	}

	if(color.a < u_alpha_cutoff) {
		discard;
	}

	vec3 lit_color = color.rgb * light_component;
	FragColor = vec4(lit_color, color.a);
}

\normalmap.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform sampler2D u_normal_texture;
uniform float u_time;
uniform float u_alpha_cutoff;

uniform vec3 u_light_ambient;

uniform vec3 u_light_pos[10];
uniform vec3 u_light_color[10];
uniform float u_light_int[10];
uniform vec3 u_light_dir[10];
uniform int u_light_count;
uniform int u_light_type[10];
uniform float u_light_min[10];
uniform float u_light_max[10];

uniform float u_light_cone_max[10];	//FOR SPOT LIGHTS
uniform float u_light_cone_min[10];		//FOR SPOT LIGHTS

uniform float u_material_shine;
uniform vec3 u_camera_pos;

out vec4 FragColor;

mat3 cotangentFrame(vec3 N, vec3 p, vec2 uv) {
    vec3 dp1 = dFdx(p);
    vec3 dp2 = dFdy(p);
    vec2 duv1 = dFdx(uv);
    vec2 duv2 = dFdy(uv);

    vec3 dp2perp = cross(dp2, N);
    vec3 dp1perp = cross(N, dp1);
    vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

    T = normalize(T);
    B = normalize(B);
    N = normalize(N);

    mat3 tbn = mat3(T, B, N);
    
    // Ensure right-handed TBN
    if (dot(cross(T, B), N) < 0.0)
        tbn[2] = -tbn[2]; // flip Z to fix handedness

    return tbn;
}


vec3 perturbNormal(vec3 N, vec3 WP, vec2 uv, vec3 normal_pixel) {
	//normal_pixel = normal_pixel * 255./127. - 128./127.;
	mat3 TBN = cotangentFrame(N, WP, uv);
	return normalize(TBN * normal_pixel);
}

void main()
{

	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, v_uv );

	vec3 texture_normal = texture( u_normal_texture, v_uv ).xyz;
	texture_normal = (texture_normal * 2.0) - 1.0;
	texture_normal = normalize(texture_normal);
	vec3 normal = perturbNormal(normalize(v_normal), v_world_position, v_uv, texture_normal);

	vec3 light_component = vec3(0.0, 0.0, 0.0);

	light_component += u_light_ambient * color.rgb;

	for(int i = 0; i < u_light_count; i++){

		if(u_light_type[i] == 1) {										//POINT
			float dist = distance(u_light_pos[i], v_world_position);
			float attenuation = 1.0 / pow(dist, 2);
			vec3 L = normalize(u_light_pos[i] - v_world_position);

			float l_dot_n = clamp(dot(L,normalize(normal)), 0.0, 1.0);
			light_component += u_light_int[i] * attenuation * u_light_color[i] * l_dot_n;

			
			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int[i] * attenuation * u_light_color[i];


		} else if (u_light_type[i] == 2) {								//SPOT
			float dist = distance(u_light_pos[i], v_world_position);
			float attenuation = 1.0 / pow(dist, 2);
			vec3 L = normalize(u_light_pos[i] - v_world_position);
			vec3 D = normalize(u_light_dir[i]);

			if(dot(L, D) < u_light_cone_max[i]) {	//check if the pixel is within the cone
				continue;
			}

			float cone_factor = (clamp(dot(L, D) , 0.0, 1.0) - (u_light_cone_max[i])) / (u_light_cone_min[i] - u_light_cone_max[i]);

			float spot_intensity = u_light_int[i] * attenuation * cone_factor;

			float l_dot_n = clamp(abs(dot(L, normal)), 0, 1.0);
			light_component += spot_intensity * u_light_color[i] * l_dot_n;

			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int[i] * attenuation * u_light_color[i];


		} else if (u_light_type[i] == 3) {								//DIRECTIONAL
			vec3 L = normalize(u_light_dir[i]);
			float l_dot_n = clamp(dot(L,normalize(normal)), 0, 1);
			light_component += u_light_int[i] * u_light_color[i] * l_dot_n;

			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int[i] * u_light_color[i];
		}


		
	}

	if(color.a < u_alpha_cutoff) {
		discard;
	}

	vec3 lit_color = color.rgb * light_component;
	FragColor = vec4(lit_color, color.a);
}



\multipass.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform sampler2D u_normal_texture;
uniform float u_time;
uniform float u_alpha_cutoff;

uniform vec3 u_light_ambient;

uniform vec3 u_light_pos;
uniform vec3 u_light_color;
uniform float u_light_int;
uniform vec3 u_light_dir;
uniform int u_light_type;
uniform float u_light_min;
uniform float u_light_max;

uniform float u_light_cone_max;	//FOR SPOT LIGHTS
uniform float u_light_cone_min;		//FOR SPOT LIGHTS

uniform float u_material_shine;
uniform vec3 u_camera_pos;

out vec4 FragColor;

mat3 cotangentFrame(vec3 N, vec3 p, vec2 uv) {
    vec3 dp1 = dFdx(p);
    vec3 dp2 = dFdy(p);
    vec2 duv1 = dFdx(uv);
    vec2 duv2 = dFdy(uv);

    vec3 dp2perp = cross(dp2, N);
    vec3 dp1perp = cross(N, dp1);
    vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

    T = normalize(T);
    B = normalize(B);
    N = normalize(N);

    mat3 tbn = mat3(T, B, N);
    
    // Ensure right-handed TBN
    if (dot(cross(T, B), N) < 0.0)
        tbn[2] = -tbn[2]; // flip Z to fix handedness

    return tbn;
}


vec3 perturbNormal(vec3 N, vec3 WP, vec2 uv, vec3 normal_pixel) {
	//normal_pixel = normal_pixel * 255./127. - 128./127.;
	mat3 TBN = cotangentFrame(N, WP, uv);
	return normalize(TBN * normal_pixel);
}

void main()
{

	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, v_uv );

	vec3 texture_normal = texture( u_normal_texture, v_uv ).xyz;
	texture_normal = (texture_normal * 2.0) - 1.0;
	texture_normal = normalize(texture_normal);
	vec3 normal = perturbNormal(normalize(v_normal), v_world_position, v_uv, texture_normal);

	vec3 light_component = vec3(0.0, 0.0, 0.0);

	light_component += u_light_ambient * color.rgb;

	if(u_light_type == 1) {										//POINT
		float dist = distance(u_light_pos, v_world_position);
		float attenuation = 1.0 / pow(dist, 2);
		vec3 L = normalize(u_light_pos - v_world_position);

		float l_dot_n = clamp(dot(L,normalize(normal)), 0.0, 1.0);
		light_component += u_light_int * attenuation * u_light_color * l_dot_n;

			
		//SPECULAR FACTOR
		vec3 R = normalize(reflect(-L, normalize(normal)));
		vec3 V = normalize(u_camera_pos - v_world_position);
		float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
		float specular = pow(r_dot_v, u_material_shine);
		light_component += specular * u_light_int * attenuation * u_light_color;


	} else if (u_light_type == 2) {								//SPOT
		float dist = distance(u_light_pos, v_world_position);
		float attenuation = 1.0 / pow(dist, 2);
		vec3 L = normalize(u_light_pos - v_world_position);
		vec3 D = normalize(u_light_dir);

		if(dot(L, D) >= u_light_cone_max) {	//check if the pixel is within the cone
			float cone_factor = (clamp(dot(L, D) , 0.0, 1.0) - (u_light_cone_max)) / (u_light_cone_min - u_light_cone_max);

			float spot_intensity = u_light_int * attenuation * cone_factor;

			float l_dot_n = clamp(abs(dot(L, normal)), 0, 1.0);
			light_component += spot_intensity * u_light_color * l_dot_n;

			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int * attenuation * u_light_color;
		}


	} else if (u_light_type == 3) {								//DIRECTIONAL
		vec3 L = normalize(u_light_dir);
		float l_dot_n = clamp(dot(L,normalize(normal)), 0, 1);
		light_component += u_light_int * u_light_color * l_dot_n;

		//SPECULAR FACTOR
		vec3 R = normalize(reflect(-L, normalize(normal)));
		vec3 V = normalize(u_camera_pos - v_world_position);
		float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
		float specular = pow(r_dot_v, u_material_shine);
		light_component += specular * u_light_int * u_light_color;
	}


	if(color.a < u_alpha_cutoff) {
		discard;
	}

	vec3 lit_color = color.rgb * light_component;
	FragColor = vec4(lit_color, color.a);
}




\debug.fs

#version 330 core

in vec3 v_position;
in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;

uniform vec4 u_color;
uniform sampler2D u_texture;
uniform sampler2D u_normal_texture;
uniform float u_time;
uniform float u_alpha_cutoff;

uniform vec3 u_light_ambient;

uniform vec3 u_light_pos[10];
uniform vec3 u_light_color[10];
uniform float u_light_int[10];
uniform vec3 u_light_dir[10];
uniform int u_light_count;
uniform int u_light_type[10];
uniform float u_light_min[10];
uniform float u_light_max[10];

uniform float u_light_cone_max[10];	//FOR SPOT LIGHTS
uniform float u_light_cone_min[10];		//FOR SPOT LIGHTS

uniform float u_material_shine;
uniform vec3 u_camera_pos;

out vec4 FragColor;

mat3 cotangentFrame(vec3 N, vec3 p, vec2 uv) {
  // get edge vectors of the pixel triangle
  vec3 dp1 = dFdx(p);
  vec3 dp2 = dFdy(p);
  vec2 duv1 = dFdx(uv);
  vec2 duv2 = dFdy(uv);

  // solve the linear system
  vec3 dp2perp = cross(dp2, N);
  vec3 dp1perp = cross(N, dp1);
  vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
  vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

  // construct a scale-invariant frame 
  float invmax = inversesqrt(max(dot(T,T), dot(B,B)));
  return mat3( normalize(T * invmax), normalize(B * invmax), N);
}

vec3 perturbNormal(vec3 N, vec3 WP, vec2 uv, vec3 normal_pixel) {
	//normal_pixel = normal_pixel * 255./127. - 128./127.;
	mat3 TBN = cotangentFrame(N, WP, uv);
	return normalize(TBN * normal_pixel);
}

void main()
{

	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, v_uv );

	vec3 texture_normal = texture( u_normal_texture, v_uv ).xyz;
	texture_normal = (texture_normal * 2.0) - 1.0;
	texture_normal = normalize(texture_normal);
	vec3 normal = perturbNormal(normalize(v_normal), v_world_position, v_uv, texture_normal);

	vec3 light_component = vec3(0.0, 0.0, 0.0);

	light_component += u_light_ambient * color.rgb;

	for(int i = 0; i < u_light_count; i++){

		if(u_light_type[i] == 1) {										//POINT
			float dist = distance(u_light_pos[i], v_world_position);
			float attenuation = 1.0 / pow(dist, 2);
			vec3 L = normalize(u_light_pos[i] - v_world_position);

			float l_dot_n = clamp(dot(L,normalize(normal)), 0.0, 1.0);
			if(dot(L,normalize(normal)) < 0.0){
				//light_component += vec3(1.0, 0, 0);
			}
			else{
				//light_component += dot(L,normalize(normal));
			}
			light_component += normal;



		} else if (u_light_type[i] == 2) {								//SPOT
			float dist = distance(u_light_pos[i], v_world_position);
			float attenuation = 1.0 / pow(dist, 2);
			vec3 L = normalize(u_light_pos[i] - v_world_position);
			vec3 D = normalize(u_light_dir[i]);

			if(dot(L, D) < u_light_cone_max[i]) {	//check if the pixel is within the cone
				continue;
			}

			float cone_factor = (clamp(dot(L, D) , 0.0, 1.0) - (u_light_cone_max[i])) / (u_light_cone_min[i] - u_light_cone_max[i]);

			float spot_intensity = u_light_int[i] * attenuation * cone_factor;

			float l_dot_n = clamp(dot(L, normal), 0, 1.0);
			//light_component += l_dot_n;


		} else if (u_light_type[i] == 3) {								//DIRECTIONAL
			continue;
		}


		
	}

	if(color.a < u_alpha_cutoff) {
		discard;
	}

	vec3 lit_color = light_component;
	FragColor = vec4(lit_color, color.a);
}

\plain.fs
#version 330 core
void main() {
}
