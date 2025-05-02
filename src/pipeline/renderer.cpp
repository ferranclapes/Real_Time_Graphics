#include "renderer.h"

#include <algorithm> //sort

#include "camera.h"
#include "../gfx/gfx.h"
#include "../gfx/shader.h"
#include "../gfx/mesh.h"
#include "../gfx/texture.h"
#include "../gfx/fbo.h"
#include "../pipeline/prefab.h"
#include "../pipeline/material.h"
#include "../pipeline/animation.h"
#include "../utils/utils.h"
#include "../extra/hdre.h"
#include "../core/ui.h"

#include "scene.h"




using namespace SCN;

//some globals
GFX::Mesh sphere;

Renderer::Renderer(const char* shader_atlas_filename)
{
	render_wireframe = false;
	render_boundaries = false;
	scene = nullptr;
	skybox_cubemap = nullptr;

	use_multipass = false;
	shadow_fbo = new GFX::FBO();
	shadow_fbo->setDepthOnly(1024, 1024);
	shadow_fbo_spot = new GFX::FBO();
	shadow_fbo_spot->setDepthOnly(1024, 1024);

	gbuffer_fbo = new GFX::FBO();
	gbuffer_fbo->create(1024, 768, 2, GL_RGBA, GL_UNSIGNED_BYTE, true);

	if (!GFX::Shader::LoadAtlas(shader_atlas_filename))
		exit(1);
	GFX::checkGLErrors();

	sphere.createSphere(1.0f);
	sphere.uploadToVRAM();
}

void Renderer::setupScene()
{
	if (scene->skybox_filename.size())
		skybox_cubemap = GFX::Texture::Get(std::string(scene->base_folder + "/" + scene->skybox_filename).c_str());
	else
		skybox_cubemap = nullptr;
}

//================= PARSE SCENE =======================

void Renderer::parseNode(SCN::Node* node, Camera* cam) {
	if (!node) {
		return;
	}

	if (node->mesh) {
		/*float rad = 0;
		for (Vector3 vertice : node->mesh->vertices) {
			float distance = vertice.distance(Vector3f(0, 0, 0));
			if (distance > rad) {
				rad = vertice.distance(Vector3f(0, 0, 0));
			}
		}

		if (!cam->testSphereInFrustum(node->model.m[3], rad)) {
			return;
		}*/

		SCN::sDrawCommand draw_com;
		draw_com.mesh = node->mesh;
		draw_com.material = node->material;
		draw_com.model = node->getGlobalMatrix();

		draw_command_list.push_back(draw_com);
	}
	for (SCN::Node* child : node->children) {
		parseNode(child, cam);
	}
}

void Renderer::parseSceneEntities(SCN::Scene* scene, Camera* cam) {

	draw_command_list.clear();
	opaque_command_list.clear();
	transparent_command_list.clear();
	
	shadow_casters.clear();

	for (int i = 0; i < scene->entities.size(); i++) {
		BaseEntity* entity = scene->entities[i];

		if (!entity->visible) {
			continue;
		}

		if (entity->getType() == eEntityType::PREFAB) {
			PrefabEntity* prefab_entt = (PrefabEntity*)entity;


			parseNode(&((PrefabEntity*)entity)->root, cam);
		}
		else if (entity->getType() == eEntityType::LIGHT) {
			LightEntity* light_entt = (LightEntity*)entity;

			SCN::sShadowCaster shadow_caster;
			shadow_caster.shadow_map = nullptr;
			shadow_caster.light = light_entt;


			shadow_casters.push_back(shadow_caster);
		}
	}

	orderDrawCommands(cam);
	
}

void Renderer::orderDrawCommands(Camera* cam) {

	//Check every node in the draw_command_list. Check the material to see if it's transparent or not
	for (sDrawCommand command : draw_command_list) {
		if (command.material->alpha_mode == eAlphaMode::NO_ALPHA) {
			opaque_command_list.push_back(command);
		}
		else {
			transparent_command_list.push_back(command);
		}
	}

	Vector3 cam_eye = cam->eye;
	//Sort both list: opaque -> front to back
	std::sort(opaque_command_list.begin(), opaque_command_list.end(),
		[&cam_eye](const SCN::sDrawCommand& a, const SCN::sDrawCommand& b) {
			Vector3 posA = Vector3(a.model.m[3]);
			Vector3 posB = Vector3(b.model.m[3]);
			return (posA - cam_eye).length() < (posB - cam_eye).length();
		});
	//Transparent -> back to front
	std::sort(transparent_command_list.begin(), transparent_command_list.end(),
		[&cam_eye](const SCN::sDrawCommand& a, const SCN::sDrawCommand& b) {
			Vector3 posA = Vector3(a.model.m[3]);
			Vector3 posB = Vector3(b.model.m[3]);
			return (posA - cam_eye).length() > (posB - cam_eye).length();
		});

	//Clear the draw_command_list and insert first the opaque and then the transparent.
	draw_command_list.clear();
	draw_command_list.insert(draw_command_list.end(), opaque_command_list.begin(), opaque_command_list.end());
	draw_command_list.insert(draw_command_list.end(), transparent_command_list.begin(), transparent_command_list.end());
}


//================= RENDER SCENE =====================

void Renderer::renderScene(SCN::Scene* scene, Camera* camera)
{
	if (deferred_rendering) {
		renderSceneDeferred(scene, camera);
	}
	else {
		renderSceneForward(scene, camera);
	}
}


//================= SHADOWS ==========================

void Renderer::renderShadowMap() {

	if(!shadow_fbo || !shadow_fbo_spot)
		return;

	//Bind the FBO for shadow rendering
	
	if(ffc) {
		glEnable(GL_CULL_FACE);					//MIRAR LO DE LES CARES
		glFrontFace(GL_CW);
	}
	else {
		glDisable(GL_CULL_FACE);
		glFrontFace(GL_CCW);
	}
	glEnable(GL_DEPTH_TEST);
	glColorMask(false, false, false, false); // Disable color writing

	for (int i = 0; i < shadow_casters.size(); i++) {
		LightEntity* light = shadow_casters[i].light;
		if (light->light_type == eLightType::POINT){	//SHADOWS NOT SUPORTED FOR POINT LIGHTS YET
			continue;
		}
		else if(light->light_type == eLightType::SPOT){
			//Bind the FBO for shadow rendering
			shadow_fbo_spot->bind();
			glClear(GL_DEPTH_BUFFER_BIT);

			//Create the light camera
			Camera light_camera;
			light_camera = light->getCameraFromLight(shadow_fbo_spot->width, shadow_fbo_spot->height);
			//Camera::current = &light_camera;

			// Save this light VP matrix for the main shader
			shadow_casters[i].light_vp = light_camera.viewprojection_matrix;

			// Render all opaque geometry to depth
			for (sDrawCommand command : opaque_command_list) {
				renderPlain(light_camera, command.model, command.mesh, command.material);
			}

			shadow_casters[i].shadow_map = shadow_fbo_spot->depth_texture;

			shadow_fbo_spot->unbind();
		}
		else {
			//Bind the FBO for shadow rendering
			shadow_fbo->bind();
			glClear(GL_DEPTH_BUFFER_BIT);

			//Create the light camera
			Camera light_camera;
			light_camera = light->getCameraFromLight(shadow_fbo->width, shadow_fbo->height);
			//Camera::current = &light_camera;

			// Save this light VP matrix for the main shader
			shadow_casters[i].light_vp = light_camera.viewprojection_matrix;

			// Render all opaque geometry to depth
			for (sDrawCommand command : opaque_command_list) {
				renderPlain(light_camera, command.model, command.mesh, command.material);
			}

			shadow_casters[i].shadow_map = shadow_fbo->depth_texture;

			shadow_fbo->unbind();
		}

		
		
	}
	if (ffc) {
		glDisable(GL_CULL_FACE);
		glFrontFace(GL_CCW);
	}
	glColorMask(true, true, true, true);

}

void Renderer::renderPlain(Camera light_cam, Matrix44 model, GFX::Mesh* mesh, SCN::Material* material) {

	// Use plain shader
	GFX::Shader* plain_shader = GFX::Shader::Get("plain");
	if (!plain_shader) return;
	plain_shader->enable();

	plain_shader->setUniform("u_model", model);
	plain_shader->setUniform("u_viewprojection", light_cam.viewprojection_matrix);
	if (material->textures[ALBEDO].texture) {
		plain_shader->setUniform("u_texture", material->textures[ALBEDO].texture, 4);
	}
	mesh->render(GL_TRIANGLES);



	plain_shader->disable();
}

//================= DEFERRED RENDERING ================

void Renderer::renderSceneDeferred(SCN::Scene* scene, Camera* camera) {
	this->scene = scene;
	setupScene();
	parseSceneEntities(scene, camera);

	geometryPass(camera);

	gbuffer_fbo->color_textures[0]->toViewport();

	//lightPass(camera);
}

void Renderer::geometryPass(Camera* camera) {
	gbuffer_fbo->bind();

	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);


	for (sDrawCommand command : opaque_command_list) {
		renderMeshWithMaterialGeometry(command.model, command.mesh, command.material);
	}

	gbuffer_fbo->unbind();
}

void Renderer::lightPass(Camera* camera) {

	GFX::Mesh* quad = GFX::Mesh::getQuad();

	//define locals to simplify coding
	GFX::Shader* shader = NULL;

	//chose a shader
	shader = GFX::Shader::Get("lightpass");

	assert(glGetError() == GL_NO_ERROR);

	//no shader? then nothing to render
	if (!shader)
		return;
	shader->enable();

	//Sending the lights
	vec3* light_pos = new vec3[shadow_casters.size()];
	vec3* light_color = new vec3[shadow_casters.size()];
	float* light_int = new float[shadow_casters.size()];
	vec3* light_dir = new vec3[shadow_casters.size()];
	int* light_type = new int[shadow_casters.size()];
	float* light_min = new float[shadow_casters.size()];
	float* light_max = new float[shadow_casters.size()];
	float* light_cone_max = new float[shadow_casters.size()]; //for spot lights
	float* light_cone_min = new float[shadow_casters.size()]; //for spot lights


	int i = 0;
	int j = 0;
	for (sShadowCaster s : shadow_casters) {
		LightEntity* light = s.light;
		light_pos[i] = light->root.getGlobalMatrix().getTranslation();
		light_color[i] = light->color;
		light_int[i] = light->intensity;
		light_dir[i] = light->root.model.frontVector();
		light_type[i] = (int)light->light_type;
		light_min[i] = light->near_distance;
		light_max[i] = light->max_distance;
		light_cone_max[i] = cos((light->cone_info.y * PI) / 180);
		light_cone_min[i] = cos((light->cone_info.x * PI) / 180);
		
		i++;
	}

	shader->setUniform3Array("u_light_pos", (float*)light_pos, min(shadow_casters.size(), 10));
	shader->setUniform3Array("u_light_color", (float*)light_color, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_int", (float*)light_int, min(shadow_casters.size(), 10));
	shader->setUniform3Array("u_light_dir", (float*)light_dir, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_type", (int*)light_type, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_min", (float*)light_min, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_max", (float*)light_max, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_cone_max", (float*)light_cone_max, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_cone_min", (float*)light_cone_min, min(shadow_casters.size(), 10));
	shader->setUniform3("u_light_ambient", scene->ambient_light.x, scene->ambient_light.y, scene->ambient_light.z);
	shader->setUniform1("u_light_count", (int)min(shadow_casters.size(), 10));

	//For specular factor:
	shader->setUniform1("u_material_shine", 32.0f);
	shader->setUniform3("u_camera_pos", camera->eye);

	delete[] light_pos;
	delete[] light_color;
	delete[] light_int;
	delete[] light_dir;
	delete[] light_type;
	delete[] light_min;
	delete[] light_max;
	delete[] light_cone_max;
	delete[] light_cone_min;


	//Bind the Gbuffers
	shader->setTexture("u_gbuffer_color", gbuffer_fbo->color_textures[0], 4);
	shader->setTexture("u_gbuffer_normal", gbuffer_fbo->color_textures[1], 5);
	shader->setTexture("u_gbuffer_depth", gbuffer_fbo->depth_texture, 6);

	shader->setUniform("u_res_inv", vec2(1.0f / gbuffer_fbo->width, 1.0f / gbuffer_fbo->height));
	shader->setMatrix44("u_inv_vp_mat", camera->inverse_viewprojection_matrix);

	quad->render(GL_TRIANGLES);

	shader->disable();

}

void Renderer::renderMeshWithMaterialGeometry(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material) {
	//in case there is nothing to do
	if (!mesh || !mesh->getNumVertices() || !material)
		return;
	assert(glGetError() == GL_NO_ERROR);

	//define locals to simplify coding
	GFX::Shader* shader = NULL;
	Camera* camera = Camera::current;

	glEnable(GL_DEPTH_TEST);
	glDepthMask(GL_TRUE);

	glColorMask(true, true, true, true);

	//chose a shader
	shader = GFX::Shader::Get("debug");

	assert(glGetError() == GL_NO_ERROR);

	//no shader? then nothing to render
	if (!shader)
		return;
	shader->enable();

	material->bind(shader);

	//For normal maps:
	shader->setUniform("u_model", model);
	if (material->textures[NORMALMAP].texture) {
		shader->setUniform("u_normal_texture", material->textures[NORMALMAP].texture, 1);
	}

	// Upload camera uniforms
	shader->setUniform("u_viewprojection", camera->viewprojection_matrix);
	shader->setUniform("u_camera_position", camera->eye);

	// Upload time, for cool shader effects
	float t = getTime();
	shader->setUniform("u_time", t);

	// Render just the verticies as a wireframe
	if (render_wireframe)
		glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);



	//do the draw call that renders the mesh into the screen
	mesh->render(GL_TRIANGLES);

	//disable shader
	shader->disable();

	//set the render state as it was before to avoid problems with future renders
	glDisable(GL_BLEND);
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
}

//================ FORWARD RENDERING ==================

void Renderer::renderSceneForward(SCN::Scene* scene, Camera* camera)
{
	this->scene = scene;
	setupScene();

	parseSceneEntities(scene, camera);

	// ================= SHADOW PASS START =================
	renderShadowMap();
	// ================= SHADOW PASS END ===================

	//set the clear color (the background color)
	glClearColor(scene->background_color.x, scene->background_color.y, scene->background_color.z, 1.0);

	// Clear the color and the depth buffer
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	GFX::checkGLErrors();

	//render skybox
	if (skybox_cubemap)
		renderSkybox(skybox_cubemap);

	// ================= RENDER PREFAB ENTITIES =================
	renderRenderable();
	// ==========================================================


}

void Renderer::renderRenderable() {

	if (use_multipass) {
		for (sDrawCommand command : opaque_command_list) {
			renderMeshWithMaterialMultipass(command.model, command.mesh, command.material);
		}
		for (sDrawCommand command : transparent_command_list) {
			renderMeshWithMaterialSinglepass(command.model, command.mesh, command.material);
		}
	}
	else {
		for (sDrawCommand command : draw_command_list) {
			renderMeshWithMaterialSinglepass(command.model, command.mesh, command.material);
		}
	}
}

// Renders a mesh given its transform and material using a single pass shader
void Renderer::renderMeshWithMaterialSinglepass(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material)
{
	//in case there is nothing to do
	if (!mesh || !mesh->getNumVertices() || !material)
		return;
	assert(glGetError() == GL_NO_ERROR);

	//define locals to simplify coding
	GFX::Shader* shader = NULL;
	Camera* camera = Camera::current;

	glEnable(GL_DEPTH_TEST);

	//chose a shader
	shader = GFX::Shader::Get("normalmap");

	assert(glGetError() == GL_NO_ERROR);

	//no shader? then nothing to render
	if (!shader)
		return;
	shader->enable();

	material->bind(shader);

	//Sending the lights
	vec3* light_pos = new vec3[shadow_casters.size()];
	vec3* light_color = new vec3[shadow_casters.size()];
	float* light_int = new float[shadow_casters.size()];
	vec3* light_dir = new vec3[shadow_casters.size()];
	int* light_type = new int[shadow_casters.size()];
	float* light_min = new float[shadow_casters.size()];
	float* light_max = new float[shadow_casters.size()];
	float* light_cone_max = new float[shadow_casters.size()]; //for spot lights
	float* light_cone_min = new float[shadow_casters.size()]; //for spot lights

	//Send the info of the shadows too
	mat4* light_vp = new mat4[shadow_casters.size()];
	GFX::Texture** shadow_map = new GFX::Texture * [shadow_casters.size()];

	int i = 0;
	int j = 0;
	for (sShadowCaster s : shadow_casters) {
		LightEntity* light = s.light;
		light_pos[i] = light->root.getGlobalMatrix().getTranslation();
		light_color[i] = light->color;
		light_int[i] = light->intensity;
		light_dir[i] = light->root.model.frontVector();
		light_type[i] = (int)light->light_type;
		light_min[i] = light->near_distance;
		light_max[i] = light->max_distance;
		light_cone_max[i] = cos((light->cone_info.y * PI) / 180);
		light_cone_min[i] = cos((light->cone_info.x * PI) / 180);
		if (light->light_type != eLightType::POINT) {
			light_vp[j] = s.light_vp;
			shadow_map[j] = s.shadow_map;
			j++;
		}

		i++;
	}

	shader->setUniform3Array("u_light_pos", (float*)light_pos, min(shadow_casters.size(), 10));
	shader->setUniform3Array("u_light_color", (float*)light_color, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_int", (float*)light_int, min(shadow_casters.size(), 10));
	shader->setUniform3Array("u_light_dir", (float*)light_dir, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_type", (int*)light_type, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_min", (float*)light_min, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_max", (float*)light_max, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_cone_max", (float*)light_cone_max, min(shadow_casters.size(), 10));
	shader->setUniform1Array("u_light_cone_min", (float*)light_cone_min, min(shadow_casters.size(), 10));
	shader->setUniform3("u_light_ambient", scene->ambient_light.x, scene->ambient_light.y, scene->ambient_light.z);
	shader->setUniform1("u_light_count", (int)min(shadow_casters.size(), 10));

	//For specular factor:
	shader->setUniform1("u_material_shine", material->shininess);
	shader->setUniform3("u_camera_pos", camera->eye);

	delete[] light_pos;
	delete[] light_color;
	delete[] light_int;
	delete[] light_dir;
	delete[] light_type;
	delete[] light_min;
	delete[] light_max;
	delete[] light_cone_max;
	delete[] light_cone_min;

	//For shadow maps:
	if (shadow_fbo && shadow_fbo->depth_texture) {
		shader->setUniform("u_shadow_map[0]", shadow_map[0], 2);
		shader->setUniform("u_shadow_map[1]", shadow_map[1], 3);
		shader->setMatrix44Array("u_light_vp", light_vp, 2);
		shader->setUniform("u_light_bias", shadow_bias);
	}

	delete[] light_vp;


	//For normal maps:
	shader->setUniform("u_model", model);
	if (material->textures[NORMALMAP].texture) {
		shader->setUniform("u_normal_texture", material->textures[NORMALMAP].texture, 1);
	}

	// Upload camera uniforms
	shader->setUniform("u_viewprojection", camera->viewprojection_matrix);
	shader->setUniform("u_camera_position", camera->eye);

	// Upload time, for cool shader effects
	float t = getTime();
	shader->setUniform("u_time", t);

	// Render just the verticies as a wireframe
	if (render_wireframe)
		glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);

	//do the draw call that renders the mesh into the screen
	mesh->render(GL_TRIANGLES);

	//disable shader
	shader->disable();

	//set the render state as it was before to avoid problems with future renders
	glDisable(GL_BLEND);
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
}

void Renderer::renderMeshWithMaterialMultipass(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material) {
	//in case there is nothing to do
	if (!mesh || !mesh->getNumVertices() || !material)
		return;
	assert(glGetError() == GL_NO_ERROR);

	//define locals to simplify coding
	GFX::Shader* shader = NULL;
	Camera* camera = Camera::current;

	glEnable(GL_DEPTH_TEST);
	glDepthFunc(GL_LEQUAL);
	glDepthMask(GL_TRUE);


	//chose a shader
	shader = GFX::Shader::Get("multipass");

	assert(glGetError() == GL_NO_ERROR);

	//no shader? then nothing to render
	if (!shader)
		return;
	shader->enable();

	material->bind(shader);

	//Sending the lights
	bool is_first_pass = true;
	for (sShadowCaster s : shadow_casters) {
		LightEntity* light = s.light;
		if (!is_first_pass) {		//If we aren't in the first light, we enable blending and disable depth writing
			glEnable(GL_BLEND);
			glBlendFunc(GL_ONE, GL_ONE);
			glDepthMask(GL_FALSE);
		}
		else {						//If we are in the first light, we disable blending and enable depth writing
			glDisable(GL_BLEND);
			glDepthMask(GL_TRUE);
		}

		//Send the info of ONE light to the shader:
		shader->setUniform3("u_light_pos", light->root.getGlobalMatrix().getTranslation());
		shader->setUniform3("u_light_color", light->color);
		shader->setUniform1("u_light_int", light->intensity);
		shader->setUniform3("u_light_dir", light->root.model.frontVector());
		shader->setUniform1("u_light_type", (int)light->light_type);
		shader->setUniform1("u_light_min", light->near_distance);
		shader->setUniform1("u_light_max", light->max_distance);
		shader->setUniform1("u_light_cone_max", (float)(cos((light->cone_info.y * PI) / 180.0)));
		shader->setUniform1("u_light_cone_min", (float)(cos((light->cone_info.x * PI) / 180.0)));

		// Only ambient in first pass
		vec3 ambient = is_first_pass ? scene->ambient_light : vec3(0.0);
		shader->setUniform3("u_light_ambient", ambient);

		// Uniforms that don’t change per light
		shader->setUniform("u_model", model);
		shader->setUniform("u_viewprojection", camera->viewprojection_matrix);
		shader->setUniform3("u_camera_pos", camera->eye);
		shader->setUniform1("u_material_shine", material->shininess);
		// Upload time, for cool shader effects
		float t = getTime();
		shader->setUniform("u_time", t);

		if (material->textures[NORMALMAP].texture)
			shader->setUniform("u_normal_texture", material->textures[NORMALMAP].texture, 1);

		if (render_wireframe)
			glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);


		// Draw the mesh
		mesh->render(GL_TRIANGLES);

		if (!is_first_pass) {
			glDisable(GL_BLEND);
			glDepthMask(GL_TRUE);
		}

		is_first_pass = false;
	}

	shader->disable();

	//set the render state as it was before to avoid problems with future renders
	glDisable(GL_BLEND);
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);

}


//================ SKYBOX ==========================

void Renderer::renderSkybox(GFX::Texture* cubemap)
{
	Camera* camera = Camera::current;

	// Apply skybox necesarry config:
	// No blending, no dpeth test, we are always rendering the skybox
	// Set the culling aproppiately, since we just want the back faces
	glDisable(GL_BLEND);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_CULL_FACE);

	if (render_wireframe)
		glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);

	GFX::Shader* shader = GFX::Shader::Get("skybox");
	if (!shader)
		return;
	shader->enable();

	// Center the skybox at the camera, with a big sphere
	Matrix44 m;
	m.setTranslation(camera->eye.x, camera->eye.y, camera->eye.z);
	m.scale(10, 10, 10);
	shader->setUniform("u_model", m);

	// Upload camera uniforms
	shader->setUniform("u_viewprojection", camera->viewprojection_matrix);
	shader->setUniform("u_camera_position", camera->eye);

	shader->setUniform("u_texture", cubemap, 0);

	sphere.render(GL_TRIANGLES);

	shader->disable();

	// Return opengl state to default
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
	glEnable(GL_DEPTH_TEST);
}


#ifndef SKIP_IMGUI

void Renderer::showUI()
{
		
	ImGui::Checkbox("Wireframe", &render_wireframe);
	ImGui::Checkbox("Boundaries", &render_boundaries);

	//add here your stuff
	//...

	ImGui::Checkbox("Deferred Rendering", &deferred_rendering);

	ImGui::Checkbox("Multipass", &use_multipass);
	ImGui::Checkbox("Forward Facing Culling", &ffc);
	ImGui::DragFloat("Shadow Bias", &shadow_bias, 0.0001f, 0.0f, 0.5f, "%.0001f");
}

#else
void Renderer::showUI() {}
#endif