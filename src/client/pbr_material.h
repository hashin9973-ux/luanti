// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Luanti contributors

#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace labpbr
{

/**
 * Resolve a LabPBR companion map for a plain source texture name.
 *
 * Texture expressions can concatenate images or apply image modifiers, so
 * their material channels cannot be safely inferred from a single sibling
 * file. Only a simple image path is accepted.
 */
inline bool getCompanionTextureName(std::string_view base_image,
		std::string_view suffix, std::string &result)
{
	result.clear();
	if (base_image.empty() || base_image.find('^') != std::string_view::npos ||
			(suffix != "_n" && suffix != "_s"))
		return false;

	const std::size_t slash = base_image.find_last_of("/\\");
	const std::size_t extension = base_image.find_last_of('.');
	if (extension == std::string_view::npos ||
			(slash != std::string_view::npos && extension < slash) ||
			extension == 0)
		return false;

	result.assign(base_image.substr(0, extension));
	result.append(suffix);
	result.append(base_image.substr(extension));
	return true;
}

constexpr bool isConductor(std::uint8_t f0_channel)
{
	return f0_channel >= 230;
}

inline float decodeDielectricF0(std::uint8_t f0_channel)
{
	return std::clamp(static_cast<float>(f0_channel) / 255.0f, 0.02f, 0.9f);
}

inline float decodeRoughness(std::uint8_t smoothness_channel)
{
	const float smoothness = static_cast<float>(smoothness_channel) / 255.0f;
	const float inverse_smoothness = 1.0f - smoothness;
	return inverse_smoothness * inverse_smoothness;
}

constexpr float decodeAmbientOcclusion(std::uint8_t ao_channel)
{
	return static_cast<float>(ao_channel) / 255.0f;
}

constexpr float decodeHeightDepth(std::uint8_t height_channel)
{
	return (255.0f - static_cast<float>(height_channel)) * (0.25f / 255.0f);
}

constexpr float decodeEmission(std::uint8_t emission_channel)
{
	return emission_channel == 255 ? 0.0f :
			static_cast<float>(emission_channel) / 254.0f;
}

inline float reconstructNormalZ(float x, float y)
{
	return std::sqrt(std::max(0.0f, 1.0f - x * x - y * y));
}

} // namespace labpbr
