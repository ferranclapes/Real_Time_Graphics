#pragma once
#include "scene.h"
#include "prefab.h"

#include "light.h"

//forward declarations
class Camera;
class Skeleton;
namespace GFX {
	class Shader;
	class Mesh;
	class FBO;
}

namespace SCN {

	class Prefab;
	class Material;

	struct sDrawCommand {
		GFX::Mesh* mesh;
		SCN::Material* material;
		Matrix44 model;
	};

	struct sShadowCaster {
		GFX::Texture* shadow_map;
		mat4 light_vp;
		LightEntity* light;
	};

	// This class is in charge of rendering anything in our system.
	// Separating the render from anything else makes the code cleaner
	class Renderer
	{
	public:
		bool render_wireframe;
		bool render_boundaries;
		bool use_multipass;
		bool ffc;
		float shadow_bias = 0.0001f;
		bool deferred_rendering = true;
		bool use_pbr = true;
		bool use_ssao = true;
		float ao_samples = 32.0f;
		float ao_radius = 0.05f;

		std::vector<SCN::sDrawCommand> draw_command_list;
		std::vector<SCN::sDrawCommand> opaque_command_list;
		std::vector<SCN::sDrawCommand> transparent_command_list;

		std::vector<vec3> ssao_points;


		//============ AMBIENT OCCLUSION ===================
		GFX::FBO* ssao_fbo;

		//================ SHADOWS =========================
		GFX::FBO* shadow_fbo;
		GFX::FBO* shadow_fbo_spot;
		mat4 light_vp;
		mat4 light_vp_spot;
		std::vector<SCN::sShadowCaster> shadow_casters;

		//==================================================


		//================ DEFERRED RENDERING ==========================
		GFX::FBO* gbuffer_fbo;

		//==============================================================

		GFX::Texture* skybox_cubemap;

		SCN::Scene* scene;

		//updated every frame
		Renderer(const char* shaders_atlas_filename );

		//just to be sure we have everything ready for the rendering
		void setupScene();

		//add here your functions
		//...

		void parseNode(SCN::Node* node, Camera* cam);

		void parseSceneEntities(SCN::Scene* scene, Camera* camera);

		void orderDrawCommands(Camera* cam);

		std::vector <vec3> generateSpherePoints(int num, float radius, bool hemi);

		//renders several elements of the scene
		void renderScene(SCN::Scene* scene, Camera* camera);
		void renderSceneForward(SCN::Scene* scene, Camera* camera);
		void renderSceneDeferred(SCN::Scene* scene, Camera* camera);

		void geometryPass(Camera* camera);
		void lightPass(Camera* camera);

		void renderRenderable();
		void renderShadowMap();
		void renderPlain(Camera light_cam, Matrix44 model, GFX::Mesh* mesh, SCN::Material* material);

		void renderAmbientOcclusion(Camera* camera);

		//render the skybox
		void renderSkybox(GFX::Texture* cubemap);
		void renderSkyboxDeferred(GFX::Texture* cubemap);

		//to render one mesh given its material and transformation matrix
		void renderMeshWithMaterialSinglepass(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material);
		void renderMeshWithMaterialMultipass(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material);

		void renderMeshWithMaterialGeometry(const Matrix44 model, GFX::Mesh* mesh, SCN::Material* material);

		void showUI();
	};

};