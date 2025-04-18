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
	// HERE =====================
	// TODO: GENERATE RENDERABLES
	// ==========================

	draw_command_list.clear();
	opaque_command_list.clear();
	transparent_command_list.clear();


	lights_list.clear();

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

			lights_list.push_back(light_entt);
		}

		// Store Prefab Entitys
		// ...
		//		Store Children Prefab Entities

		// Store Lights
		// ...
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

void Renderer::renderScene(SCN::Scene* scene, Camera* camera)
{
	this->scene = scene;
	setupScene();

	parseSceneEntities(scene, camera);

	// ================= SHADOW PASS START =================
	//	renderShadowMap();
	// ================= SHADOW PASS END ===================

	//set the clear color (the background color)
	glClearColor(scene->background_color.x, scene->background_color.y, scene->background_color.z, 1.0);

	// Clear the color and the depth buffer
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	GFX::checkGLErrors();

	//render skybox
	if(skybox_cubemap)
		//renderSkybox(skybox_cubemap);

	// ================= RENDER PREFAB ENTITIES =================
	renderRenderable();
	// ==========================================================
	

}


void Renderer::renderShadowMap() {

	if(!shadow_fbo)
		return;

	//Bind the FBO for shadow rendering
	shadow_fbo->bind();

	glClear(GL_DEPTH_BUFFER_BIT);
	glEnable(GL_DEPTH_TEST);
	glDepthFunc(GL_LEQUAL);
	glDepthMask(GL_TRUE);
	//glColorMask(false, false, false, false); // Disable color writing

	// Set viewport to shadow map resolution
	glViewport(0, 0, shadow_fbo->width, shadow_fbo->height);

	//================== TEMPORARY CODE =================
	// Choose light (e.g., first directional or spotlight)
	LightEntity* light = nullptr;
	for (auto l : lights_list) {
		if (l->light_type == eLightType::DIRECTIONAL) {
			light = l;
			break;
		}
	}
	if (!light)
		return;
	//===================================================

	//Create the light camera
	Camera light_camera;
	light_camera = light->getCameraFromLight(shadow_fbo->width, shadow_fbo->height);
	//Camera::current = &light_camera;

	// Save this light VP matrix for the main shader
	mat4 light_viewproj_matrix = light_camera.viewprojection_matrix;

	// Render all opaque geometry to depth
	for(sDrawCommand command : opaque_command_list) {
		renderPlain(light_camera, command.model, command.mesh, command.material);
	}


	//// Read back depth buffer here
	//int w = shadow_fbo->width;
	//int h = shadow_fbo->height;

	//unsigned int* depth_data = new unsigned int[w * h];
	//glReadPixels(0, 0, w, h, GL_DEPTH_COMPONENT, GL_UNSIGNED_INT, depth_data);

	//std::cout << "Depth data:" << std::endl;
	//for (int i = 0; i < 10; ++i) {
	//	float normalized = (float)depth_data[i] / 16777215.0f;
	//	std::cout << i << "] = " << normalized << std::endl;
	//}


	//delete[] depth_data;


	//glColorMask(true, true, true, true);
	shadow_fbo->unbind();
	//glViewport(0, 0, , window_height); // Restore main screen resolution

}

void Renderer::renderPlain(Camera light_cam, Matrix44 model, GFX::Mesh* mesh, SCN::Material* material) {

	// Use plain shader
	GFX::Shader* plain_shader = GFX::Shader::Get("plain");
	if (!plain_shader) return;
	plain_shader->enable();

	plain_shader->setUniform("u_model", model);
	plain_shader->setUniform("u_viewprojection", light_cam.viewprojection_matrix);
	mesh->render(GL_TRIANGLES);



	plain_shader->disable();
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

// Renders a mesh given its transform and material using a single pass shader
void Renderer::renderMeshWithMaterialSinglepass(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material)
{
	//in case there is nothing to do
	if (!mesh || !mesh->getNumVertices() || !material )
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
	vec3* light_pos = new vec3[lights_list.size()];
	vec3* light_color = new vec3[lights_list.size()];
	float* light_int = new float[lights_list.size()];
	vec3* light_dir = new vec3[lights_list.size()];
	int* light_type = new int[lights_list.size()];
	float* light_min = new float[lights_list.size()];
	float* light_max = new float[lights_list.size()];
	float* light_cone_max = new float[lights_list.size()]; //for spot lights
	float* light_cone_min = new float[lights_list.size()]; //for spot lights

	int i = 0;
	for (LightEntity* light : lights_list) {
		if (light->light_type != eLightType::POINT){
			//continue;
		}
		light_pos[i] = light->root.getGlobalMatrix().getTranslation();
		light_color[i] = light->color;
		light_int[i] = light->intensity;
		light_dir[i] = light->root.model.frontVector();
		light_type[i] = (int) light->light_type;
		light_min[i] = light->near_distance;
		light_max[i] = light->max_distance;
		light_cone_max[i] = cos((light->cone_info.y * PI)/180);
		light_cone_min[i] = cos((light->cone_info.x * PI) / 180);
		i++;
	}

	shader->setUniform3Array("u_light_pos", (float*) light_pos, min(lights_list.size(), 10));
	shader->setUniform3Array("u_light_color", (float*) light_color, min(lights_list.size(), 10));
	shader->setUniform1Array("u_light_int", (float*) light_int, min(lights_list.size(), 10));
	shader->setUniform3Array("u_light_dir", (float*) light_dir, min(lights_list.size(), 10));
	shader->setUniform1Array("u_light_type", (int*) light_type, min(lights_list.size(), 10));
	shader->setUniform1Array("u_light_min", (float*) light_min, min(lights_list.size(), 10));
	shader->setUniform1Array("u_light_max", (float*) light_max, min(lights_list.size(), 10));
	shader->setUniform1Array("u_light_cone_max", (float*) light_cone_max, min(lights_list.size(), 10));
	shader->setUniform1Array("u_light_cone_min", (float*) light_cone_min, min(lights_list.size(), 10));
	shader->setUniform3("u_light_ambient", scene->ambient_light.x, scene->ambient_light.y, scene->ambient_light.z);
	shader->setUniform1("u_light_count", (int) min(lights_list.size(), 10));

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



	//upload uniforms
	shader->setUniform("u_model", model);
	if (material->textures[NORMALMAP].texture) {
		shader->setUniform("u_normal_texture", material->textures[NORMALMAP].texture, 1);
	}

	// Upload camera uniforms
	shader->setUniform("u_viewprojection", camera->viewprojection_matrix);
	shader->setUniform("u_camera_position", camera->eye);

	// Upload time, for cool shader effects
	float t = getTime();
	shader->setUniform("u_time", t );

	// Render just the verticies as a wireframe
	if (render_wireframe)
		glPolygonMode( GL_FRONT_AND_BACK, GL_LINE );

	//do the draw call that renders the mesh into the screen
	mesh->render(GL_TRIANGLES);

	//disable shader
	shader->disable();

	//set the render state as it was before to avoid problems with future renders
	glDisable(GL_BLEND);
	glPolygonMode( GL_FRONT_AND_BACK, GL_FILL );
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
	for (LightEntity* light : lights_list) {
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
		shader->setUniform1("u_light_cone_max", (float) (cos((light->cone_info.y * PI) / 180.0)));
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

#ifndef SKIP_IMGUI

void Renderer::showUI()
{
		
	ImGui::Checkbox("Wireframe", &render_wireframe);
	ImGui::Checkbox("Boundaries", &render_boundaries);

	//add here your stuff
	//...

	ImGui::Checkbox("Multipass", &use_multipass);
}

#else
void Renderer::showUI() {}
#endif