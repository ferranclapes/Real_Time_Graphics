#include "light.h"

#include "../core/ui.h"
#include "../utils/utils.h"

SCN::LightEntity::LightEntity()
{
	light_type = eLightType::POINT;
	color.set(1, 1, 1);
	cone_info.set(25, 40);
	intensity = 1;
	max_distance = 100;
	cast_shadows = false;
	shadow_bias = 0.001;
	near_distance = 0.1;
	area = 1000;
}

void SCN::LightEntity::configure(cJSON* json)
{
	color = readJSONVector3(json, "color", color );
	intensity = readJSONNumber(json, "intensity", intensity);
	max_distance = readJSONNumber(json, "max_dist", max_distance);
	cast_shadows = readJSONBool(json, "cast_shadows", cast_shadows);

	cone_info.x = readJSONNumber(json, "cone_start", cone_info.x );
	cone_info.y = readJSONNumber(json, "cone_end", cone_info.y );
	area = readJSONNumber(json, "area", area);
	near_distance = readJSONNumber(json, "near_dist", near_distance);

	std::string light_type_str = readJSONString(json, "light_type", "");
	if (light_type_str == "POINT")
		light_type = eLightType::POINT;
	if (light_type_str == "SPOT")
		light_type = eLightType::SPOT;
	if (light_type_str == "DIRECTIONAL")
		light_type = eLightType::DIRECTIONAL;
}

void SCN::LightEntity::serialize(cJSON* json)
{
	writeJSONVector3(json, "color", color);
	writeJSONNumber(json, "intensity", intensity);
	writeJSONNumber(json, "max_dist", max_distance);
	writeJSONBool(json, "cast_shadows", cast_shadows);
	writeJSONNumber(json, "near_dist", near_distance);

	if (light_type == eLightType::SPOT)
	{
		writeJSONNumber(json, "cone_start", cone_info.x);
		writeJSONNumber(json, "cone_end", cone_info.y);
	}
	if (light_type == eLightType::DIRECTIONAL)
		writeJSONNumber(json, "area", area);

	if (light_type == eLightType::POINT)
		writeJSONString(json, "light_type", "POINT");
	if (light_type == eLightType::SPOT)
		writeJSONString(json, "light_type", "SPOT");
	if (light_type == eLightType::DIRECTIONAL)
		writeJSONString(json, "light_type", "DIRECTIONAL");
}

Camera SCN::LightEntity::getCameraFromLight(float fbo_width, float fbo_height)
{
	Camera cam;

	Matrix44 light_model = this->root.getGlobalMatrix();
	Vector3f pos = light_model.getTranslation();

	cam.lookAt(pos, light_model * vec3(0.0f, 0.0f, -1.0f), Vector3f(0.0f, 1.0f, 0.0f));

	if (this->light_type == SCN::eLightType::DIRECTIONAL) {
		float half_size = this->area / 2.0f;

		cam.setOrthographic(-half_size, half_size,
			-half_size, half_size,
			this->near_distance, this->max_distance);
	}
	else if (this->light_type == SCN::eLightType::SPOT) {

		float aspect = fbo_height > 0.0f ? fbo_width / fbo_height : 1.0f;

		cam.setPerspective(this->cone_info.y * 2.0f, aspect, //the aspect ratio of the FBO
			this->near_distance, this->max_distance);
	}

	return cam;
}


