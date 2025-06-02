//example of some shaders compiled
flat basic.vs flat.fs
texture basic.vs texture.fs
skybox basic.vs skybox.fs
deferredskybox basic.vs deferredskybox.fs
depth quad.vs depth.fs
multi basic.vs multi.fs
forward_singlepass basic.vs forward_singlepass.fs
forward_multipass basic.vs forward_multipass.fs
plain basic.vs plain.fs
geometry basic.vs gbuffer_fill.fs
lightpass quad.vs lightpass.fs
forward_PBR_singlepass basic.vs forward_PBR_singlepass.fs
forward_PBR_multipass basic.vs forward_PBR_multipass.fs
deferred_PBR_geometry basic.vs deferred_PBR_geometry.fs
deferred_PBR_lightpass quad.vs deferred_PBR_lightpass.fs
ambient_occlusion quad.vs ambient_occlusion.fs
ambient_occlusion_hemi quad.vs ambient_occlusion_hemi.fs
plain_rsm basic.vs plain_rsm.fs
indirect quad.vs indirect.fs
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

//============================================================================
\forward_singlepass.fs

#version 330 core
#include "pertubnormals"
#include "hdr_functions"

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

//FOR SHADOWS
uniform sampler2D u_shadow_map[2];
uniform mat4 u_light_vp[2];
uniform float u_light_bias;

uniform float u_material_shine;
uniform vec3 u_camera_pos;

uniform bool u_hdr;

out vec4 FragColor;

void main()
{

	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, v_uv );
	if(u_hdr){
		color.xyz = degamma(color.xyz);
	}

	//======================== APPLY NORMAL MAP ==========================
	vec3 texture_normal = texture( u_normal_texture, v_uv ).xyz;
	texture_normal = (texture_normal * 2.0) - 1.0;
	texture_normal = normalize(texture_normal);
	vec3 normal = perturbNormal(normalize(v_normal), v_world_position, v_uv, texture_normal);
	//====================================================================

	
	

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

			//======================== SHADOWS ==========================
			vec4 shadow_coord = u_light_vp[0] * vec4(v_world_position, 1.0);
			shadow_coord.z -= u_light_bias;		//Apply bias before dividing by w
			shadow_coord /= shadow_coord.w;
			vec2 shadow_uv = shadow_coord.xy * 0.5 + 0.5;
			float current_depth = shadow_coord.z * 0.5 + 0.5;
			float closest_depth = texture(u_shadow_map[0], shadow_uv).r;
			float shadow = current_depth > closest_depth ? 0 : 1.0;
			//==========================================================

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
			light_component += spot_intensity * u_light_color[i] * l_dot_n * shadow;

			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int[i] * attenuation * u_light_color[i] * shadow;


		} else if (u_light_type[i] == 3) {								//DIRECTIONAL
			//======================== SHADOWS ==========================
			vec4 shadow_coord = u_light_vp[1] * vec4(v_world_position, 1.0);
			shadow_coord.z -= u_light_bias;		//Apply bias before dividing by w
			shadow_coord /= shadow_coord.w;
			vec2 shadow_uv = shadow_coord.xy * 0.5 + 0.5;
			float current_depth = shadow_coord.z * 0.5 + 0.5;
			float closest_depth = texture(u_shadow_map[1], shadow_uv).r;
			float shadow = current_depth > closest_depth ? 0 : 1.0;
			//==========================================================


			vec3 L = normalize(u_light_dir[i]);
			float l_dot_n = clamp(dot(L,normalize(normal)), 0, 1);
			light_component += u_light_int[i] * u_light_color[i] * l_dot_n * shadow;

			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int[i] * u_light_color[i] * shadow;
		}


		
	}

	if(color.a < u_alpha_cutoff) {
		discard;
	}

	vec3 lit_color = color.rgb * light_component;
	if(u_hdr){
		color.xyz = gamma(color.xyz);
	}
	FragColor = vec4(lit_color, color.a);
}

//========================================================================================================================

\forward_multipass.fs

#version 330 core
#include "pertubnormals"
#include "hdr_functions"

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

uniform bool u_hdr;

out vec4 FragColor;


void main()
{

	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, v_uv );
	if(u_hdr){
		color.xyz = degamma(color.xyz);
	}

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
	if(u_hdr){
		lit_color.xyz = gamma(lit_color.xyz);
	}
	FragColor = vec4(lit_color, color.a);
}

//========================================================================================================================

\plain.fs
#version 330 core

uniform sampler2D u_texture;
in vec2 v_uv;

void main() {
	float alpha = texture(u_texture, v_uv).a;
	if(alpha == 0.0){
		discard;
	}
}

//========================================================================================================================

\gbuffer_fill.fs
#version 330 core
#include "pertubnormals"

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


uniform float u_material_shine;
uniform vec3 u_camera_pos;

layout(location = 0) out vec4 gbuffer_albedo;
layout(location = 1) out vec4 gbuffer_normal_mat;
layout(location = 3) out vec4 gbuffer_normal; // store normal without perturbation
out vec4 FragColor;


void main()
{
    vec4 color = u_color * texture(u_texture, v_uv);

    vec3 texture_normal = texture(u_normal_texture, v_uv).xyz;
    texture_normal = (texture_normal * 2.0) - 1.0;
    texture_normal = normalize(texture_normal);
    vec3 normal = perturbNormal(normalize(v_normal), v_world_position, v_uv, texture_normal);

    if(color.a < u_alpha_cutoff) {
        //discard;
    }

    gbuffer_albedo = vec4(color.rgb, 1.0); // store only the color
	gbuffer_normal_mat = vec4(normalize(normal) * 0.5 + 0.5, 1.0); // store normal encoded in 0..1 range
	gbuffer_normal = vec4(normalize(v_normal) * 0.5 + 0.5 , 1.0); //store normal without perturbation

	FragColor = vec4(vec3(gl_FragCoord.z), 1.0);
}

//========================================================================================================================

\deferredskybox.fs

#version 330 core

in vec3 v_position;

uniform samplerCube u_texture;
uniform vec3 u_camera_position;
out vec4 FragColor;

uniform vec2 u_res_inv;
uniform mat4 u_inv_vp_mat;
uniform sampler2D u_gbuffer_depth;

void main()
{

//================ GET UV AND RECONSTRUCT POSITION ===================
	vec2 uv = gl_FragCoord.xy * u_res_inv;

	float depth = texture(u_gbuffer_depth, uv).r;

	float depth_clip = depth * 2.0 - 1.0;

	vec2 uv_clip = uv * 2.0 - 1.0;
	vec4 clip_coords = vec4(uv_clip.x, uv_clip.y, depth_clip, 1.0);

	vec4 not_norm_w_p = u_inv_vp_mat * clip_coords;
	vec3 world_pos = not_norm_w_p.xyz / not_norm_w_p.w;
	//====================================================================


	vec3 E = world_pos - u_camera_position;
	vec4 color = texture( u_texture, E );
	FragColor = color;
}

//========================================================================================================================

\lightpass.fs
#version 330 core
#include "hdr_functions"

in vec2 v_uv;

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

//FOR SHADOWS
uniform sampler2D u_shadow_map[2];
uniform mat4 u_light_vp[2];
uniform float u_light_bias;

uniform float u_material_shine;
uniform vec3 u_camera_pos;

//FROM THE DEFERRED RENDERING
uniform vec2 u_res_inv;
uniform mat4 u_inv_vp_mat;
uniform sampler2D u_gbuffer_albedo;
uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_depth;

//FROM SSAO
uniform sampler2D u_ssao_texture;
uniform bool u_use_ssao;

uniform bool u_hdr;

layout(location = 0) out vec4 FragColor;

void main()
{

	//================ GET UV AND RECONSTRUCT POSITION ===================
	vec2 uv = gl_FragCoord.xy * u_res_inv;

	float depth = texture(u_gbuffer_depth, uv).r;

	float depth_clip = depth * 2.0 - 1.0;

	vec2 uv_clip = uv * 2.0 - 1.0;
	vec4 clip_coords = vec4(uv_clip.x, uv_clip.y, depth_clip, 1.0);

	vec4 not_norm_w_p = u_inv_vp_mat * clip_coords;
	vec3 world_pos = not_norm_w_p.xyz / not_norm_w_p.w;
	//====================================================================

	
	vec3 normal = texture(u_gbuffer_normal, v_uv).xyz * 2.0 - 1.0;

	
	if (depth == 1.0) {
    // Fragment is part of the skybox — skip lighting
    discard;
	}

	vec4 color = u_color;
	color = texture( u_gbuffer_albedo, uv);															//CAREFULL HERE!!!!!
	if(u_hdr){
		color.xyz = degamma(color.xyz);
	}

	vec3 light_component = vec3(0.0, 0.0, 0.0);

	if(u_use_ssao){
		vec4 ssao = texture(u_ssao_texture, uv);
		light_component += ssao.rgb * color.rgb;
	}
	else{
		light_component += vec3(1.0, 1.0, 1.0) * color.rgb;
	}

	for(int i = 0; i < u_light_count; i++){

		if(u_light_type[i] == 1) {										//POINT
			float dist = abs(distance(u_light_pos[i], world_pos));
			float attenuation = 1.0 / pow(dist, 2);
			vec3 L = normalize(u_light_pos[i] - world_pos);

			float l_dot_n = clamp(dot(L,normalize(normal)), 0.0, 1.0);
			light_component += u_light_int[i] * attenuation * u_light_color[i] * l_dot_n;

			
			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - world_pos);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int[i] * attenuation * u_light_color[i];


		} else if (u_light_type[i] == 2) {								//SPOT

			//======================== SHADOWS ==========================
			vec4 shadow_coord = u_light_vp[0] * vec4(world_pos, 1.0);
			shadow_coord.z -= u_light_bias;		//Apply bias before dividing by w
			shadow_coord /= shadow_coord.w;
			vec2 shadow_uv = shadow_coord.xy * 0.5 + 0.5;
			float current_depth = shadow_coord.z * 0.5 + 0.5;
			float closest_depth = texture(u_shadow_map[0], shadow_uv).r;
			float shadow = current_depth > closest_depth ? 0 : 1.0;
			//==========================================================

			float dist = distance(u_light_pos[i], world_pos);
			float attenuation = 1.0 / pow(dist, 2);
			vec3 L = normalize(u_light_pos[i] - world_pos);
			vec3 D = normalize(u_light_dir[i]);

			if(dot(L, D) < u_light_cone_max[i]) {	//check if the pixel is within the cone
				continue;
			}

			float cone_factor = (clamp(dot(L, D) , 0.0, 1.0) - (u_light_cone_max[i])) / (u_light_cone_min[i] - u_light_cone_max[i]);

			float spot_intensity = u_light_int[i] * attenuation * cone_factor;

			float l_dot_n = clamp(abs(dot(L, normal)), 0, 1.0);
			light_component += spot_intensity * u_light_color[i] * l_dot_n * shadow;

			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - world_pos);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int[i] * attenuation * u_light_color[i] * shadow;


		} else if (u_light_type[i] == 3) {								//DIRECTIONAL
			//======================== SHADOWS ==========================
			vec4 shadow_coord = u_light_vp[1] * vec4(world_pos, 1.0);
			shadow_coord.z -= u_light_bias;		//Apply bias before dividing by w
			shadow_coord /= shadow_coord.w;
			vec2 shadow_uv = shadow_coord.xy * 0.5 + 0.5;
			float current_depth = shadow_coord.z * 0.5 + 0.5;
			float closest_depth = texture(u_shadow_map[1], shadow_uv).r;
			float shadow = current_depth > closest_depth ? 0 : 1.0;
			//==========================================================


			vec3 L = normalize(u_light_dir[i]);
			float l_dot_n = clamp(dot(L,normalize(normal)), 0, 1);
			light_component += u_light_int[i] * u_light_color[i] * l_dot_n * shadow;

			//SPECULAR FACTOR
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - world_pos);
			float r_dot_v = clamp(dot(R, V), 0.0, 1.0);
			float specular = pow(r_dot_v, u_material_shine);
			light_component += specular * u_light_int[i] * u_light_color[i] * shadow;
		}


		
	}

	if(color.a < u_alpha_cutoff) {
		discard;
	}

	vec3 lit_color = color.rgb * light_component;
	if(u_hdr){
		lit_color.xyz = gamma(lit_color.xyz);
	}
	FragColor = vec4(lit_color, color.a);
	
}


//========================================================================================================================

\forward_PBR_singlepass.fs

#version 330 core
#include "PBR_functions"
#include "pertubnormals"
#include "hdr_functions"

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

//FOR SHADOWS
uniform sampler2D u_shadow_map[2];
uniform mat4 u_light_vp[2];
uniform float u_light_bias;

uniform float u_material_shine;
uniform vec3 u_camera_pos;

//FROM PBR
uniform sampler2D u_metallic_roughness_texture;

uniform bool u_hdr;

out vec4 FragColor;

void main()
{

	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, v_uv );

	//======================== APPLY NORMAL MAP ==========================
	vec3 texture_normal = texture( u_normal_texture, v_uv ).xyz;
	texture_normal = (texture_normal * 2.0) - 1.0;
	texture_normal = normalize(texture_normal);
	vec3 normal = perturbNormal(normalize(v_normal), v_world_position, v_uv, texture_normal);
	//====================================================================

	//=============== EXTRACT METALLIC ROUGHNESS DATA ====================
	vec4 metallic_roughness = texture(u_metallic_roughness_texture, uv);
	float ambient_occlusion = metallic_roughness.r;
	float roughness = metallic_roughness.g;
	float metallic = metallic_roughness.b;
	//====================================================================
	
	
	if(u_hdr){
		color.xyz = degamma(color.xyz);
	}

	vec3 light_component = vec3(0.0, 0.0, 0.0);

	light_component += u_light_ambient * color.rgb * ambient_occlusion;

	for(int i = 0; i < u_light_count; i++){

		if(u_light_type[i] == 1) {										//POINT
			float dist = distance(u_light_pos[i], v_world_position);
			float attenuation = 1.0 / pow(dist, 2);


			vec3 L = normalize(u_light_pos[i] - v_world_position);
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			vec3 H = normalize(L + V);

			vec3 specular = cookTorranceBRDF(L, V, normal, H, roughness, metallic, color);

			light_component += u_light_int[i] * attenuation * u_light_color[i] * ((color.rgb/3.141592) + specular);


		} else if (u_light_type[i] == 2) {								//SPOT

			//======================== SHADOWS ==========================
			vec4 shadow_coord = u_light_vp[0] * vec4(v_world_position, 1.0);
			shadow_coord.z -= u_light_bias;		//Apply bias before dividing by w
			shadow_coord /= shadow_coord.w;
			vec2 shadow_uv = shadow_coord.xy * 0.5 + 0.5;
			float current_depth = shadow_coord.z * 0.5 + 0.5;
			float closest_depth = texture(u_shadow_map[0], shadow_uv).r;
			float shadow = current_depth > closest_depth ? 0 : 1.0;
			//==========================================================

			float dist = distance(u_light_pos[i], v_world_position);
			float attenuation = 1.0 / pow(dist, 2);


			vec3 L = normalize(u_light_pos[i] - v_world_position);
			vec3 D = normalize(u_light_dir[i]);
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			vec3 H = normalize(L + V);

			if(dot(L, D) < u_light_cone_max[i]) {	//check if the pixel is within the cone
				continue;
			}

			float cone_factor = (clamp(dot(L, D) , 0.0, 1.0) - (u_light_cone_max[i])) / (u_light_cone_min[i] - u_light_cone_max[i]);

			float spot_intensity = u_light_int[i] * attenuation * cone_factor;

			vec3 specular = cookTorranceBRDF(L, V, normal, H, roughness, metallic, color);

			light_component += spot_intensity * u_light_color[i] * shadow * ((color.rgb/3.141592) + specular);


		} else if (u_light_type[i] == 3) {								//DIRECTIONAL
			//======================== SHADOWS ==========================
			vec4 shadow_coord = u_light_vp[1] * vec4(v_world_position, 1.0);
			shadow_coord.z -= u_light_bias;		//Apply bias before dividing by w
			shadow_coord /= shadow_coord.w;
			vec2 shadow_uv = shadow_coord.xy * 0.5 + 0.5;
			float current_depth = shadow_coord.z * 0.5 + 0.5;
			float closest_depth = texture(u_shadow_map[1], shadow_uv).r;
			float shadow = current_depth > closest_depth ? 0 : 1.0;
			//==========================================================


			vec3 L = normalize(u_light_dir[i]);
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - v_world_position);
			vec3 H = normalize(L + V);

			vec3 specular = cookTorranceBRDF(L, V, normal, H, roughness, metallic, color);

			light_component += u_light_int[i] * u_light_color[i] * shadow * ((color.rgb/3.141592) + specular);
		}


		
	}

	if(color.a < u_alpha_cutoff) {
		discard;
	}

	vec3 lit_color = color.rgb * light_component;
	
	if(u_hdr){
		lit_color.xyz = gamma(lit_color.xyz);
	}
	FragColor = vec4(lit_color, color.a);
		
}

//=======================================================================================================================
\forward_PBR_multipass.fs

#version 330 core
#include "pertubnormals"
#include "PBR_functions"
#include "hdr_functions"

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

//FROM PBR
uniform sampler2D u_metallic_roughness_texture;

uniform bool u_hdr;

out vec4 FragColor;


void main()
{

	vec2 uv = v_uv;
	vec4 color = u_color;
	color *= texture( u_texture, v_uv );

	//======================== APPLY NORMAL MAP ==========================
	vec3 texture_normal = texture( u_normal_texture, v_uv ).xyz;
	texture_normal = (texture_normal * 2.0) - 1.0;
	texture_normal = normalize(texture_normal);
	vec3 normal = perturbNormal(normalize(v_normal), v_world_position, v_uv, texture_normal);
	//====================================================================

	//=============== EXTRACT METALLIC ROUGHNESS DATA ====================
	vec4 metallic_roughness = texture(u_metallic_roughness_texture, uv);
	float ambient_occlusion = metallic_roughness.r;
	float roughness = metallic_roughness.g;
	float metallic = metallic_roughness.b;
	//====================================================================

	vec3 light_component = vec3(0.0, 0.0, 0.0);

	if(u_hdr){
		color.xyz = degamma(color.xyz);
	}

	light_component += u_light_ambient * color.rgb * ambient_occlusion;

	if(u_light_type == 1) {										//POINT
		float dist = distance(u_light_pos, v_world_position);
		float attenuation = 1.0 / pow(dist, 2);

		vec3 L = normalize(u_light_pos - v_world_position);
		vec3 R = normalize(reflect(-L, normalize(normal)));
		vec3 V = normalize(u_camera_pos - v_world_position);
		vec3 H = normalize(L + V);

		vec3 specular = cookTorranceBRDF(L, V, normal, H, roughness, metallic, color);

		light_component += u_light_int * attenuation * u_light_color * ((color.rgb/3.141592) + specular);


	} else if (u_light_type == 2) {								//SPOT
		float dist = distance(u_light_pos, v_world_position);
		float attenuation = 1.0 / pow(dist, 2);

		vec3 L = normalize(u_light_pos - v_world_position);
		vec3 D = normalize(u_light_dir);
		vec3 R = normalize(reflect(-L, normalize(normal)));
		vec3 V = normalize(u_camera_pos - v_world_position);
		vec3 H = normalize(L + V);

		if(dot(L, D) >= u_light_cone_max) {	//check if the pixel is within the cone
			float cone_factor = (clamp(dot(L, D) , 0.0, 1.0) - (u_light_cone_max)) / (u_light_cone_min - u_light_cone_max);

			float spot_intensity = u_light_int * attenuation * cone_factor;

			vec3 specular = cookTorranceBRDF(L, V, normal, H, roughness, metallic, color);

			light_component += spot_intensity * u_light_color * ((color.rgb/3.141592) + specular);
		}


	} else if (u_light_type == 3) {								//DIRECTIONAL
		vec3 L = normalize(u_light_dir);
		vec3 R = normalize(reflect(-L, normalize(normal)));
		vec3 V = normalize(u_camera_pos - v_world_position);
		vec3 H = normalize(L + V);

		vec3 specular = cookTorranceBRDF(L, V, normal, H, roughness, metallic, color);

		light_component += u_light_int * u_light_color * ((color.rgb/3.141592) + specular);
	}


	if(color.a < u_alpha_cutoff) {
		discard;
	}

	vec3 lit_color = color.rgb * light_component;
	if(u_hdr){
		lit_color.xyz = gamma(lit_color.xyz);
	}
	FragColor = vec4(lit_color, color.a);
}

//=======================================================================================================================
\deferred_PBR_geometry.fs
#version 330 core
#include "pertubnormals"

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


uniform float u_material_shine;
uniform vec3 u_camera_pos;

uniform sampler2D u_metallic_roughness_texture;

layout(location = 0) out vec4 gbuffer_albedo;
layout(location = 1) out vec4 gbuffer_normal_mat;
layout(location = 2) out vec4 gbuffer_metallic_roughness;
layout(location = 3) out vec4 gbuffer_normal;
out vec4 FragColor;


void main()
{
    vec4 color = u_color * texture(u_texture, v_uv);

    vec3 texture_normal = texture(u_normal_texture, v_uv).xyz;
    texture_normal = (texture_normal * 2.0) - 1.0;
    texture_normal = normalize(texture_normal);
    vec3 normal = perturbNormal(normalize(v_normal), v_world_position, v_uv, texture_normal);

	vec4 metallic_roughness = texture(u_metallic_roughness_texture, v_uv);

    if(color.a < u_alpha_cutoff) {
        //discard;
    }

    gbuffer_albedo = vec4(color.rgb, 1.0); // store only the color
	gbuffer_normal_mat = vec4(normalize(normal) * 0.5 + 0.5, 1.0); // store normal encoded in 0..1 range
	gbuffer_metallic_roughness = vec4(metallic_roughness.rgb, 1.0); // store metallic and roughness
	gbuffer_normal = vec4(normalize(v_normal) * 0.5 + 0.5 , 1.0); //store normal without perturbation

	FragColor = vec4(vec3(gl_FragCoord.z), 1.0);
}


//======================================================================================================================
\deferred_PBR_lightpass.fs
#version 330 core
#include "PBR_functions"
#include "hdr_functions"

in vec2 v_uv;

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

//FOR SHADOWS
uniform sampler2D u_shadow_map[2];
uniform mat4 u_light_vp[2];
uniform float u_light_bias;

uniform float u_material_shine;
uniform vec3 u_camera_pos;

//FROM THE DEFERRED RENDERING
uniform vec2 u_res_inv;
uniform mat4 u_inv_vp_mat;
uniform sampler2D u_gbuffer_albedo;
uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_depth;
uniform sampler2D u_gbuffer_metallic_roughness;

//FROM SSAO
uniform sampler2D u_ssao_texture;
uniform bool u_use_ssao;

uniform bool u_hdr;

layout(location = 0) out vec4 FragColor;

void main()
{

	//================ GET UV AND RECONSTRUCT POSITION ===================
	vec2 uv = gl_FragCoord.xy * u_res_inv;

	float depth = texture(u_gbuffer_depth, uv).r;

	float depth_clip = depth * 2.0 - 1.0;

	vec2 uv_clip = uv * 2.0 - 1.0;
	vec4 clip_coords = vec4(uv_clip.x, uv_clip.y, depth_clip, 1.0);

	vec4 not_norm_w_p = u_inv_vp_mat * clip_coords;
	vec3 world_pos = not_norm_w_p.xyz / not_norm_w_p.w;
	//====================================================================

	
	vec3 normal = texture(u_gbuffer_normal, v_uv).xyz * 2.0 - 1.0;

	
	if (depth == 1.0) {
    // Fragment is part of the skybox — skip lighting
    discard;
	}

	vec4 color = texture( u_gbuffer_albedo, uv);
	
	if(u_hdr){
		color.xyz = degamma(color.xyz);
	}

	vec4 metallic_roughness = texture(u_gbuffer_metallic_roughness, uv);

	vec3 light_component = vec3(0.0, 0.0, 0.0);

	if(u_use_ssao) {
		vec3 ssao = texture(u_ssao_texture, uv).xyz;
		light_component += u_light_ambient * color.rgb * ssao;
	} else {
		light_component += u_light_ambient * color.rgb * metallic_roughness.x;
	}

	for(int i = 0; i < u_light_count; i++){

		if(u_light_type[i] == 1) {										//POINT
			float dist = abs(distance(u_light_pos[i], world_pos));
			float attenuation = 1.0 / pow(dist, 2);
			vec3 L = normalize(u_light_pos[i] - world_pos);
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - world_pos);
			vec3 H = normalize(L + V);

			vec3 specular = cookTorranceBRDF(L, V, normal, H, metallic_roughness.g, metallic_roughness.b, color);


			light_component += u_light_int[i] * attenuation * u_light_color[i] * ((color.rgb/3.141592) + specular);


		} else if (u_light_type[i] == 2) {								//SPOT

			//======================== SHADOWS ==========================
			vec4 shadow_coord = u_light_vp[0] * vec4(world_pos, 1.0);
			shadow_coord.z -= u_light_bias;		//Apply bias before dividing by w
			shadow_coord /= shadow_coord.w;
			vec2 shadow_uv = shadow_coord.xy * 0.5 + 0.5;
			float current_depth = shadow_coord.z * 0.5 + 0.5;
			float closest_depth = texture(u_shadow_map[0], shadow_uv).r;
			float shadow = current_depth > closest_depth ? 0 : 1.0;
			//==========================================================

			float dist = distance(u_light_pos[i], world_pos);
			float attenuation = 1.0 / pow(dist, 2);
			vec3 L = normalize(u_light_pos[i] - world_pos);
			vec3 D = normalize(u_light_dir[i]);
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - world_pos);
			vec3 H = normalize(L + V);

			if(dot(L, D) < u_light_cone_max[i]) {	//check if the pixel is within the cone
				continue;
			}



			float cone_factor = (clamp(dot(L, D) , 0.0, 1.0) - (u_light_cone_max[i])) / (u_light_cone_min[i] - u_light_cone_max[i]);

			float spot_intensity = u_light_int[i] * attenuation * cone_factor;

			vec3 specular = cookTorranceBRDF(L, V, normal, H, metallic_roughness.g, metallic_roughness.b, color);

			light_component += spot_intensity * u_light_color[i] * shadow* ((color.rgb/3.141592) + specular);


		} else if (u_light_type[i] == 3) {								//DIRECTIONAL
			//======================== SHADOWS ==========================
			vec4 shadow_coord = u_light_vp[1] * vec4(world_pos, 1.0);
			shadow_coord.z -= u_light_bias;		//Apply bias before dividing by w
			shadow_coord /= shadow_coord.w;
			vec2 shadow_uv = shadow_coord.xy * 0.5 + 0.5;
			float current_depth = shadow_coord.z * 0.5 + 0.5;
			float closest_depth = texture(u_shadow_map[1], shadow_uv).r;
			float shadow = current_depth > closest_depth ? 0 : 1.0;
			//==========================================================


			vec3 L = normalize(u_light_dir[i]);
			vec3 R = normalize(reflect(-L, normalize(normal)));
			vec3 V = normalize(u_camera_pos - world_pos);
			vec3 H = normalize(L + V);

			vec3 specular = cookTorranceBRDF(L, V, normal, H, metallic_roughness.g, metallic_roughness.b, color);

			light_component += u_light_int[i] * u_light_color[i] * shadow * ((color.rgb/3.141592) + specular);
		}


		
	}

	if(color.a < u_alpha_cutoff) {
		discard;
	}

	vec3 lit_color = color.rgb * light_component;
	if(u_hdr){
		lit_color.xyz = gamma(lit_color.xyz);
	}
	FragColor = vec4(lit_color, color.a);
	
}


//========================================================================================================================
\PBR_functions

vec3 fresnelTerm(vec3 V, vec3 H, vec4 color, float metallic){
	vec3 F0 = mix(vec3(0.04), color.rgb, metallic); // Fresnel reflectance at normal incidence

	return F0 + (1.0 - F0) * pow(1.0 - max(dot(H, V), 0.0), 5.0);
}

float normalDistributionFunction(vec3 H, vec3 N, float roughness) {
	float a = roughness * roughness;
	float a2 = a * a;

	float NdotH = max(dot(N, H), 0.0);
	float NdotH2 = NdotH * NdotH;

	float denom = (NdotH2 * (a2 - 1.0) + 1.0);
	denom = 3.14159265359 * denom * denom;

	return a2 / denom;
}

float g1(vec3 V, vec3 N, float roughness) {
	float a = roughness * roughness;
	float k = a / 2.0;
	float NdotV = max(dot(N, V), 0.0);
	return NdotV / (NdotV * (1.0 - k) + k);
}

float geometryTerm(vec3 L, vec3 V, vec3 N, float roughness) {;

	return g1(L, N, roughness) * g1(V, N, roughness);
}

vec3 cookTorranceBRDF(vec3 L, vec3 V, vec3 N, vec3 H, float roughness, float metallic, vec4 color) {
	float D = normalDistributionFunction(H, N, roughness);
	float G = geometryTerm(L, V, N, roughness);
	vec3 F = fresnelTerm(V, H, color, metallic);

	return (D * G * F) / (4.0 * max(dot(N, L), 0.001) * max(dot(N, V), 0.001));
}

//========================================================================================================================
\pertubnormals

mat3 cotangentFrame(vec3 N, vec3 p, vec2 uv) {
    vec3 dp1 = dFdx(p);
    vec3 dp2 = dFdy(p);
    vec2 duv1 = dFdx(uv);
    vec2 duv2 = dFdy(uv);

    vec3 dp2perp = cross(dp2, N);
    vec3 dp1perp = cross(N, dp1);
    vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

    float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
	return mat3(T * invmax, B * invmax, N);
}


vec3 perturbNormal(vec3 N, vec3 WP, vec2 uv, vec3 normal_pixel) {

	mat3 TBN = cotangentFrame(N, WP, uv);
	return normalize(TBN * normal_pixel);
}

//========================================================================================================================
\ambient_occlusion.fs
#version 330 core

in vec2 v_uv;

uniform float u_ao_radius;
uniform float u_ao_samples;
uniform vec3[64] u_samples_pos;

uniform mat4 u_p_matrix;
uniform mat4 u_inv_p_matrix;
uniform mat4 u_v_matrix;

uniform vec2 u_res_inv;

uniform sampler2D u_depth_texture;
uniform sampler2D u_gbuffer_normal;

layout(location = 0) out vec4 FragColor;


void main() {
	//================ GET UV AND CLIP COORDINATES ===================
	vec2 uv = v_uv + 0.5 * u_res_inv;

	float depth = texture(u_depth_texture, uv).r;

	if(depth >= 1.0) {
		FragColor = vec4(1.0);
		return;
	}

	vec4 clip_coords = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 view_sample_origin = u_inv_p_matrix * clip_coords;
	view_sample_origin /= view_sample_origin.w;
	//====================================================================

	float ao_term = 0.0;
	for(int i = 0; i < u_ao_samples; i++) {
		vec3 view_sample = u_samples_pos[i];
		//view_sample *= u_ao_radius;
		view_sample += view_sample_origin.xyz;

		vec4 proj_sample = u_p_matrix * vec4(view_sample, 1.0);
		proj_sample /= proj_sample.w;
		vec2 sample_uv = proj_sample.xy * 0.5 + 0.5;

		float sample_depth = texture(u_depth_texture, sample_uv).r;

		proj_sample.z = proj_sample.z * 0.5 + 0.5;
		
		if(sample_depth > proj_sample.z) {
			ao_term += 1.0;
}

		
	}
	ao_term /= u_ao_samples;
	FragColor = vec4(ao_term, ao_term, ao_term, 1.0);


}


//========================================================================================================================
\ambient_occlusion_hemi.fs
#version 330 core

in vec2 v_uv;

uniform float u_ao_radius;
uniform float u_ao_samples;
uniform vec3[64] u_samples_pos;

uniform mat4 u_p_matrix;
uniform mat4 u_inv_p_matrix;
uniform mat4 u_v_matrix;

uniform vec2 u_res_inv;

uniform sampler2D u_depth_texture;
uniform sampler2D u_gbuffer_normal;

layout(location = 0) out vec4 FragColor;


void main() {
	//================ GET UV AND CLIP COORDINATES ===================
	vec2 uv = v_uv + 0.5 * u_res_inv;

	float depth = texture(u_depth_texture, uv).r;

	if(depth >= 1.0) {
		FragColor = vec4(1.0);
		return;
	}

	vec4 clip_coords = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 view_sample_origin = u_inv_p_matrix * clip_coords;
	view_sample_origin /= view_sample_origin.w;
	//====================================================================

	vec3 normal = texture(u_gbuffer_normal, uv).xyz * 2.0 - 1.0;
	normal = (u_v_matrix * vec4(normal, 0.0)).xyz;

	vec3 v = vec3(0.0, 1.0, 0.0);

	vec3 T = normalize(v - normal * dot(v, normal));
	vec3 B = cross(normal, T);

	mat3 rotmat = mat3(T, B, normal);

	float ao_term = 0.0;
	for(int i = 0; i < u_ao_samples; i++) {
		vec3 view_sample = rotmat * u_samples_pos[i];
		//view_sample *= u_ao_radius;
		view_sample += view_sample_origin.xyz;

		vec4 proj_sample = u_p_matrix * vec4(view_sample, 1.0);
		proj_sample /= proj_sample.w;
		vec2 sample_uv = proj_sample.xy * 0.5 + 0.5;

		float sample_depth = texture(u_depth_texture, sample_uv).r;

		proj_sample.z = proj_sample.z * 0.5 + 0.5;
		
		if(sample_depth > proj_sample.z) {
			ao_term += 1.0;
}

		
	}
	ao_term /= u_ao_samples;
	FragColor = vec4(ao_term, ao_term, ao_term, 1.0);


}


//==============================================================================================================
\hdr_functions

vec3 degamma(vec3 c){
	return pow(c, vec3(2.2));
}

vec3 gamma (vec3 c){
	return pow(c, vec3(1.0/2.2));
} 

//==============================================================================================================

\plain_rsm.fs
#version 330 core

in vec2 v_uv;
in vec3 v_world_position;
in vec3 v_normal;

uniform sampler2D u_albedo_texture;
uniform vec3 u_light_color;

layout(location = 0) out vec4 FragPos;
layout(location = 1) out vec4 FragN;
layout(location = 2) out vec4 FragFlux;

void main() {
	float alpha = texture(u_albedo_texture, v_uv).a;
	if(alpha == 0.0){
		discard;
	}

	FragPos = vec4(v_world_position, 1.0);
	FragN = vec4(normalize(v_normal) * 0.5 + 0.5, 1.0); // store normal encoded in 0..1 range

	vec4 albedo = texture(u_albedo_texture, v_uv);
	FragFlux = vec4(albedo.rgb * u_light_color, 1.0); // store flux in RGB and alpha as 1.0
}

//==============================================================================================================
\indirect.fs
#version 330 core

in vec2 v_uv;

uniform mat4 lightViewProjMatrix;
uniform mat4 u_inv_vp_mat;

uniform sampler2D u_rsm_depth;
uniform sampler2D u_rsm_position;
uniform sampler2D u_rsm_normal;
uniform sampler2D u_rsm_flux;

uniform float u_sample_radius;
uniform vec3[1000] u_samples_pos;
uniform int u_sample_count;
uniform vec2 u_texel_size;

uniform sampler2D u_gbuffer_normal;
uniform sampler2D u_gbuffer_depth;

uniform bool u_is_dir;

layout(location = 0) out vec4 FragColor;

void main() {

	vec3 indirectLight = vec3(0.0);
	float totalWeight = 0.0;

	vec3 fragNormal = texture(u_gbuffer_normal, v_uv).xyz * 2.0 - 1.0;

	//================ GET WORLD POSITION OF FRAGMENT ===================
	float z = texture(u_gbuffer_depth, v_uv).r; // NDC depth
	vec4 clip_coord = vec4(v_uv.x * 2.0 - 1.0, v_uv.y * 2.0 - 1.0, z * 2.0 - 1.0, 1.0);
	vec4 not_norm_w_p = u_inv_vp_mat * clip_coord;
	vec3 world_pos = not_norm_w_p.xyz / not_norm_w_p.w;


	//================ GET FRAGMENT POSITION IN LIGHT SPACE ===================
	vec4 fragLightSpace = lightViewProjMatrix * vec4(world_pos,1);

	vec3 lightNDC = fragLightSpace.xyz / fragLightSpace.w;

	vec2 st = lightNDC.xy * 0.5 + 0.5;

	float lightDepth = lightNDC.z * 0.5 + 0.5;
	//================================================================

	if(st.x < 0.0 || st.x > 1.0 || st.y < 0.0 || st.y > 1.0) {
		discard;
	}
	if(lightDepth < 0.0 || lightDepth >= 1.0) {
		discard; // Skip fragments outside the light's view frustum
	}

	for (int i = 0; i < u_sample_count; i++) {
	//================ SAMPLE POSITIONS ===================
		vec2 sample = u_samples_pos[i].xy;
		vec2 offset = sample * 0.05;

		vec2 sampleST = st + offset;
		if(sampleST.x < 0.0 || sampleST.x > 1.0 || sampleST.y < 0.0 || sampleST.y > 1.0) {
			continue; // Skip samples outside the texture bounds
		} 
	//=====================================================
	//================ RETRIEVE DATA FROM RPM =============
		vec3 rsm_pos = texture(u_rsm_position, sampleST).xyz;
		vec3 rsm_normal = texture(u_rsm_normal, sampleST).xyz * 2.0 - 1.0;
		vec3 rsm_flux = texture(u_rsm_flux, sampleST).xyz;
	//=====================================================

		vec3 toFrag = world_pos.xyz - rsm_pos;
	
		float dist4 = pow(length(toFrag), 4); // Avoid division by zero
	
		vec3 lightDir = (toFrag);

		float ndotL = max(dot(rsm_normal, lightDir), 0.0);
		float nl = max(dot(fragNormal, -lightDir), 0.0);


		vec3 contrib = rsm_flux * ndotL * nl / dist4; // Avoid division by zero
		

		indirectLight += contrib * (u_samples_pos[i].z * u_samples_pos[i].z);
		

	}
	//indirectLight /= float(u_sample_count);

	FragColor = vec4(indirectLight, 1.0);
	
	if(indirectLight.x > 1.0 || indirectLight.y > 1.0 || indirectLight.z > 1.0){
	FragColor = vec4(0, 0.5, 0, 1);
	}
	if(indirectLight.x > 1.0 && indirectLight.y > 1.0 && indirectLight.z > 1.0){
	FragColor = vec4(0.5, 0, 0, 1);
	}
}