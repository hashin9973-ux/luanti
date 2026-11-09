// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Luanti contributors

#include "test.h"

#include "client/pbr_material.h"

#include <cmath>
#include <string>

class TestPBR : public TestBase
{
public:
	TestPBR() { TestManager::registerTestModule(this); }
	const char *getName() override { return "TestPBR"; }
	void runTests(IGameDef *) override;

private:
	void testCompanionTextureNames();
	void testLabPBRMaterialChannels();
};

static TestPBR g_test_pbr;

void TestPBR::runTests(IGameDef *)
{
	TEST(testCompanionTextureNames);
	TEST(testLabPBRMaterialChannels);
}

void TestPBR::testCompanionTextureNames()
{
	std::string name;
	UASSERT(labpbr::getCompanionTextureName("stone.png", "_n", name));
	UASSERTEQ(std::string, name, "stone_n.png");
	UASSERT(labpbr::getCompanionTextureName("nodes/stone.tga", "_s", name));
	UASSERTEQ(std::string, name, "nodes/stone_s.tga");
	UASSERT(labpbr::getCompanionTextureName("textures/stone.normal.png", "_n", name));
	UASSERTEQ(std::string, name, "textures/stone.normal_n.png");

	UASSERT(!labpbr::getCompanionTextureName("", "_n", name));
	UASSERT(!labpbr::getCompanionTextureName("stone", "_n", name));
	UASSERT(!labpbr::getCompanionTextureName("stone.png^overlay.png", "_n", name));
	UASSERT(!labpbr::getCompanionTextureName("stone.png^[opacity:160", "_s", name));
	UASSERT(!labpbr::getCompanionTextureName("stone.png", "_height", name));
	UASSERTEQ(std::string, name, "");
}

void TestPBR::testLabPBRMaterialChannels()
{
	// LabPBR smoothness is perceptual and converts to roughness quadratically.
	UASSERT(std::fabs(labpbr::decodeRoughness(0) - 1.0f) < 1e-6f);
	UASSERT(std::fabs(labpbr::decodeRoughness(255)) < 1e-6f);
	UASSERT(std::fabs(labpbr::decodeRoughness(127) -
			std::pow(1.0f - 127.0f / 255.0f, 2.0f)) < 1e-6f);

	// Green stores linear dielectric F0 through 229; 230 begins conductors.
	UASSERT(!labpbr::isConductor(229));
	UASSERT(labpbr::isConductor(230));
	UASSERT(labpbr::isConductor(255));
	UASSERT(std::fabs(labpbr::decodeDielectricF0(0) - 0.02f) < 1e-6f);
	UASSERT(std::fabs(labpbr::decodeDielectricF0(229) -
			229.0f / 255.0f) < 1e-6f);

	// AO is linear; normal-map alpha encodes zero-to-25% depth in reverse.
	UASSERT(labpbr::decodeAmbientOcclusion(0) == 0.0f);
	UASSERT(labpbr::decodeAmbientOcclusion(255) == 1.0f);
	UASSERT(labpbr::decodeHeightDepth(255) == 0.0f);
	UASSERT(std::fabs(labpbr::decodeHeightDepth(0) - 0.25f) < 1e-6f);

	// Specular alpha 255 is the non-emissive sentinel; 254 is full emission.
	UASSERT(labpbr::decodeEmission(0) == 0.0f);
	UASSERT(labpbr::decodeEmission(254) == 1.0f);
	UASSERT(labpbr::decodeEmission(255) == 0.0f);

	UASSERT(std::fabs(labpbr::reconstructNormalZ(0.0f, 0.0f) - 1.0f) < 1e-6f);
	UASSERT(labpbr::reconstructNormalZ(0.8f, 0.8f) == 0.0f);
}
