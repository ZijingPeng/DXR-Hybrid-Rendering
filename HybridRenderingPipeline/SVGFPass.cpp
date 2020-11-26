/**********************************************************************************************************************
# Copyright (c) 2018, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
# following conditions are met:
#  * Redistributions of code must retain the copyright notice, this list of conditions and the following disclaimer.
#  * Neither the name of NVIDIA CORPORATION nor the names of its contributors may be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT
# SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
# OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**********************************************************************************************************************/

#include "./SVGFPass.h"

// TODO: on compile, allocate FBOs based on size

namespace {
	// Where is our shader located?
	const char kPackLinearZAndNormalShader[] = "SVGF\\SVGFPackLinearZAndNormal.ps.hlsl";
	const char kReprojectShader[] = "SVGF\\SVGFReproject.ps.hlsl";
	const char kAtrousShader[] = "SVGF\\SVGFAtrous.ps.hlsl";
	const char kFilterMomentShader[] = "SVGF\\SVGFFilterMoments.ps.hlsl";
	const char kFinalModulateShader[] = "SVGF\\SVGFFinalModulate.ps.hlsl";

	// Input buffers
	const char kInputBufferAlbedo[] = "Albedo";
	const char kInputBufferColor[] = "Color";
	const char kInputBufferEmission[] = "Emission";
	const char kInputBufferWorldPosition[] = "WorldPosition";
	const char kInputBufferWorldNormal[] = "WorldNormal";
	const char kInputBufferPosNormalFwidth[] = "PositionNormalFwidth";
	const char kInputBufferLinearZ[] = "LinearZ";
	const char kInputBufferMotionVector[] = "MotionVec";

	// Internal buffer names
	const char kInternalBufferPreviousLinearZAndNormal[] = "Previous Linear Z and Packed Normal";
	const char kInternalBufferPreviousLighting[] = "Previous Lighting";
	const char kInternalBufferPreviousMoments[] = "Previous Moments";

	// Output buffer name
	const char kOutputBufferFilteredImage[] = "Filtered image";
};

// Define our constructor methods
SVGFPass::SharedPtr SVGFPass::create(const std::string& bufferOut)
{
	return SharedPtr(new SVGFPass(bufferOut));
}

SVGFPass::SVGFPass(const std::string& bufferOut)
	: ::RenderPass("SVGF Pass", "SVGF Options")
{
	mOutputTexName = bufferOut;
}

bool SVGFPass::initialize(RenderContext* pRenderContext, ResourceManager::SharedPtr pResManager)
{
	// Stash our resource manager; ask for the texture the developer asked us to write
	mpResManager = pResManager;
	mpResManager->requestTextureResources({
		kInputBufferAlbedo,
		kInputBufferColor,
		kInputBufferEmission,
		kInputBufferWorldPosition,
		kInputBufferWorldNormal,
		kInputBufferPosNormalFwidth,
		kInputBufferLinearZ,
		kInputBufferMotionVector
	});

	mpResManager->requestTextureResources({
		kInternalBufferPreviousLinearZAndNormal,
		kInternalBufferPreviousLighting,
		kInternalBufferPreviousMoments
	});
	mpResManager->requestTextureResource(kOutputBufferFilteredImage);

	// Set the default scene to load
	//mpResManager->setDefaultSceneName("Data/pink_room/pink_room.fscene");

	// Create our graphics state and an accumulation shader
	mpGfxState = GraphicsState::create();
	
	mpPackLinearZAndNormal = FullscreenLaunch::create(kPackLinearZAndNormalShader);
	mpReprojection = FullscreenLaunch::create(kReprojectShader);
	mpAtrous = FullscreenLaunch::create(kAtrousShader);
	mpFilterMoments = FullscreenLaunch::create(kFilterMomentShader);
	mpFinalModulate = FullscreenLaunch::create(kFinalModulateShader);
	return true;
}

void SVGFPass::initScene(RenderContext* pRenderContext, Scene::SharedPtr pScene)
{

	// When our renderer moves around we want to reset accumulation, so stash the scene pointer
	mpScene = std::dynamic_pointer_cast<RtScene>(pScene);
	if (!mpScene) return;
	mpLambertShader->setLights(mpScene->getLights());
}

void SVGFPass::resize(uint32_t width, uint32_t height)
{
	// We need a framebuffer to attach to our graphics pipe state (when running our full-screen pass).  We can ask our
	//    resource manager to create one for us, with specified width, height, and format and one color buffer.
	mpInternalFbo = ResourceManager::createFbo(width, height, ResourceFormat::RGBA32Float);
	mpGfxState->setFbo(mpInternalFbo);
}

void SVGFPass::renderGui(Gui* pGui)
{
	// Print the name of the buffer we're accumulating from and into.  Add a blank line below that for clarity
	pGui->addText((std::string("Direct Ligting buffer:   ") + mOutputTexName).c_str());
	pGui->addText("");

	// Display a count of accumulated frames
	pGui->addText("");
}

void SVGFPass::execute(RenderContext* pRenderContext)
{
	// Grab the texture to write to
	Texture::SharedPtr pDstTex = mpResManager->getTexture(mOutputTexName);

	Texture::SharedPtr pAlbedoTexture = mpResManager->getTexture(kInputBufferAlbedo);
	Texture::SharedPtr pColorTexture = mpResManager->getTexture(kInputBufferColor);
	Texture::SharedPtr pEmissionTexture = mpResManager->getTexture(kInputBufferEmission);
	Texture::SharedPtr pWorldPositionTexture = mpResManager->getTexture(kInputBufferWorldPosition);
	Texture::SharedPtr pWorldNormalTexture = mpResManager->getTexture(kInputBufferWorldNormal);
	Texture::SharedPtr pPosNormalFwidthTexture = mpResManager->getTexture(kInputBufferPosNormalFwidth);
	Texture::SharedPtr pLinearZTexture = mpResManager->getTexture(kInputBufferLinearZ);
	Texture::SharedPtr pMotionVectorTexture = mpResManager->getTexture(kInputBufferMotionVector);

	Texture::SharedPtr pOutputTexture = mpResManager->getTexture(kOutputBufferFilteredImage);

	// If our input texture is invalid, or we've been asked to skip accumulation, do nothing.
	if (!pOutputTexture) return;

	if (mBuffersNeedClear) {
		clearBuffers(pRenderContext);
		mBuffersNeedClear = false;
	}

	if (!mFilterEnabled) {
		pRenderContext->blit(pColorTexture->getSRV(), pOutputTexture->getRTV());
		return;
	}


	//mpLambertShader->setLights(mpScene->getLights());
	//// Pass our G-buffer textures down to the HLSL so we can shade
	//auto shaderVars = mpLambertShader->getVars();
	//shaderVars["gPos"] = mpResManager->getTexture("WorldPosition");
	//shaderVars["gNorm"] = mpResManager->getTexture("WorldNormal");
	//shaderVars["gDiffuseMatl"] = mpResManager->getTexture("MaterialDiffuse");

	//// Execute the accumulation shader
	//mpLambertShader->execute(pRenderContext, mpGfxState);

	//// We've accumulated our result.  Copy that back to the input/output buffer
	//pRenderContext->blit(mpInternalFbo->getColorTexture(0)->getSRV(), pDstTex->getRTV());
}

void SVGFPass::clearBuffers(RenderContext* pRenderContext) {
	mpResManager->clearTexture(mpResManager->getTexture(kInternalBufferPreviousLinearZAndNormal), glm::vec4(0.f));
	mpResManager->clearTexture(mpResManager->getTexture(kInternalBufferPreviousLighting), glm::vec4(0.f));
	mpResManager->clearTexture(mpResManager->getTexture(kInternalBufferPreviousMoments), glm::vec4(0.f));
}
