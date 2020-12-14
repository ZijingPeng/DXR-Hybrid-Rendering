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

#include "./SVGFShadowPass.h"

// TODO: on compile, allocate FBOs based on size

namespace {
	// Where is our shader located?
	const char kReprojectShader[] = "SVGFShadow\\SVGFReproject.ps.hlsl";
	const char kAtrousShader[] = "SVGFShadow\\SVGFAtrous.ps.hlsl";
	const char kFilterMomentShader[] = "SVGFShadow\\SVGFFilterMoments.ps.hlsl";

	// Input buffers
	const char kInputBufferWorldPosition[] = "WorldPosition";
	const char kInputBufferWorldNormal[] = "WorldNormal";
	const char kInputBufferLinearZAndNormal[] = "linearZAndNormal";
	const char kInputBufferMotionVecAndFWidth[] = "MotiveVectorsAndFWidth";

	// Internal buffer names
	const char kInternalBufferPreviousLinearZAndNormal[] = "Shadow Previous Linear Z and Packed Normal";
	const char kInternalBufferPreviousLighting[] = "Shadow Previous Lighting";
	const char kInternalBufferPreviousMoments[] = "Shadow Previous Moments";
};

// Define our constructor methods
SVGFShadowPass::SharedPtr SVGFShadowPass::create(const std::string& bufferToAccumulate,
                                                 const std::string& directShadowBuffer,
                                                 const std::string& aoBuffer)
{
	return SharedPtr(new SVGFShadowPass(bufferToAccumulate, directShadowBuffer, aoBuffer));
}

SVGFShadowPass::SVGFShadowPass(const std::string& bufferToAccumulate,
                                const std::string& directShadowBuffer,
                                const std::string& aoBuffer)
	: ::RenderPass("SVGF Shadow Pass", "SVGF Shadow Options")
{
	 mOutputTexName = bufferToAccumulate;
    mDirectShadowTexName = directShadowBuffer;
    mAoTexName = aoBuffer;
}

bool SVGFShadowPass::initialize(RenderContext* pRenderContext, ResourceManager::SharedPtr pResManager)
{
	// Stash our resource manager; ask for the texture the developer asked us to write
	mpResManager = pResManager;
	
	 mpResManager->requestTextureResources({
		kInputBufferWorldPosition,
		kInputBufferWorldNormal,
		kInputBufferLinearZAndNormal,
		kInputBufferMotionVecAndFWidth
	});

	mpResManager->requestTextureResources({
		kInternalBufferPreviousLinearZAndNormal,
		kInternalBufferPreviousLighting,
		kInternalBufferPreviousMoments
	});
	mpResManager->requestTextureResource(mOutputTexName);

	// Create our graphics state and an accumulation shader
	mpGfxState = GraphicsState::create();
	
	mpReprojection = FullscreenLaunch::create(kReprojectShader);
	mpAtrous = FullscreenLaunch::create(kAtrousShader);
	mpFilterMoments = FullscreenLaunch::create(kFilterMomentShader);
	return true;
}

void SVGFShadowPass::allocateFbos(glm::uvec2 dim)
{
  {
    Fbo::Desc desc;
    desc.setSampleCount(0);
    desc.setColorTarget(0, Falcor::ResourceFormat::RGBA32Float); // illumination
    desc.setColorTarget(1, Falcor::ResourceFormat::RG32Float);   // moments
    desc.setColorTarget(2, Falcor::ResourceFormat::R16Float);    // history length
	  mpCurReprojFbo = FboHelper::create2D(dim.x, dim.y, desc);
    mpPrevReprojFbo = FboHelper::create2D(dim.x, dim.y, desc);
  }

  {
    Fbo::Desc desc;
    desc.setColorTarget(0, Falcor::ResourceFormat::RGBA32Float);
    mpPingPongFbo[0]  = FboHelper::create2D(dim.x, dim.y, desc);
    mpPingPongFbo[1]  = FboHelper::create2D(dim.x, dim.y, desc);
    mpFilteredPastFbo = FboHelper::create2D(dim.x, dim.y, desc);
    mpFilteredIlluminationFbo       = FboHelper::create2D(dim.x, dim.y, desc);
  }

  mBuffersNeedClear = true;
}

void SVGFShadowPass::resize(uint32_t width, uint32_t height)
{
	  glm::uvec2 dim(width, height);
    allocateFbos(dim);
}


void SVGFShadowPass::clearBuffers(RenderContext* pRenderContext) {
  pRenderContext->clearFbo(mpPingPongFbo[0].get(), float4(0), 1.0f, 0, FboAttachmentType::All);
  pRenderContext->clearFbo(mpPingPongFbo[1].get(), float4(0), 1.0f, 0, FboAttachmentType::All);
  pRenderContext->clearFbo(mpFilteredPastFbo.get(), float4(0), 1.0f, 0, FboAttachmentType::All);
  pRenderContext->clearFbo(mpCurReprojFbo.get(), float4(0), 1.0f, 0, FboAttachmentType::All);
  pRenderContext->clearFbo(mpPrevReprojFbo.get(), float4(0), 1.0f, 0, FboAttachmentType::All);
  pRenderContext->clearFbo(mpFilteredIlluminationFbo.get(), float4(0), 1.0f, 0, FboAttachmentType::All);

	mpResManager->clearTexture(mpResManager->getTexture(kInternalBufferPreviousLinearZAndNormal), glm::vec4(0.f));
	mpResManager->clearTexture(mpResManager->getTexture(kInternalBufferPreviousLighting), glm::vec4(0.f));
	mpResManager->clearTexture(mpResManager->getTexture(kInternalBufferPreviousMoments), glm::vec4(0.f));
}

void SVGFShadowPass::renderGui(Gui* pGui)
{
  int dirty = 0;
  dirty |= (int)pGui->addCheckBox(mFilterEnabled ? "SVGF enabled" : "SVGF disabled", mFilterEnabled);

  pGui->addText("");
  pGui->addText("Number of filter iterations.  Which");
  pGui->addText("    iteration feeds into future frames?");
  dirty |= (int)pGui->addIntVar("Iterations", mFilterIterations, 2, 10, 1);
  dirty |= (int)pGui->addIntVar("Feedback", mFeedbackTap, -1, mFilterIterations - 2, 1);

  pGui->addText("");
  pGui->addText("Contol edge stopping on bilateral fitler");
  dirty |= (int)pGui->addFloatVar("For Color", mPhiColor, 0.0f, 10000.0f, 0.01f);
  dirty |= (int)pGui->addFloatVar("For Normal", mPhiNormal, 0.001f, 1000.0f, 0.2f);

  pGui->addText("");
  pGui->addText("How much history should be used?");
  pGui->addText("    (alpha; 0 = full reuse; 1 = no reuse)");
  dirty |= (int)pGui->addFloatVar("Alpha", mAlpha, 0.0f, 1.0f, 0.001f);
  dirty |= (int)pGui->addFloatVar("Moments Alpha", mMomentsAlpha, 0.0f, 1.0f, 0.001f);

  if (dirty) mBuffersNeedClear = true;
}

void SVGFShadowPass::execute(RenderContext* pRenderContext)
{
	Texture::SharedPtr pShadowTexture = mpResManager->getTexture(mDirectShadowTexName);
	Texture::SharedPtr pAoTexture = mpResManager->getTexture(mAoTexName);
	Texture::SharedPtr pWorldPositionTexture = mpResManager->getTexture(kInputBufferWorldPosition);
	Texture::SharedPtr pWorldNormalTexture = mpResManager->getTexture(kInputBufferWorldNormal);
	Texture::SharedPtr pLinearZAndNormalTexture = mpResManager->getTexture(kInputBufferLinearZAndNormal);
	Texture::SharedPtr pMotionVectorAndFWidthTexture = mpResManager->getTexture(kInputBufferMotionVecAndFWidth);
	Texture::SharedPtr pOutputTexture = mpResManager->getTexture(mOutputTexName);

  Texture::SharedPtr pPrevLinearZAndNormalTexture = mpResManager->getTexture(kInternalBufferPreviousLinearZAndNormal);

	// If our input texture is invalid, or we've been asked to skip accumulation, do nothing.
	if (!pOutputTexture) return;

	if (mBuffersNeedClear) {
		clearBuffers(pRenderContext);
		mBuffersNeedClear = false;
	}

	if (!mFilterEnabled) {
		pRenderContext->blit(pShadowTexture->getSRV(), pOutputTexture->getRTV());
		return;
	}
  
  computeReprojection(pRenderContext, pShadowTexture, pAoTexture, pMotionVectorAndFWidthTexture, pLinearZAndNormalTexture, pPrevLinearZAndNormalTexture);
  
  computeFilteredMoments(pRenderContext, pLinearZAndNormalTexture);

  computeAtrousDecomposition(pRenderContext, pLinearZAndNormalTexture);

  pRenderContext->blit(mpPingPongFbo[0]->getColorTexture(0)->getSRV(), pOutputTexture->getRTV());

  std::swap(mpCurReprojFbo, mpPrevReprojFbo);
  pRenderContext->blit(pLinearZAndNormalTexture->getSRV(), pPrevLinearZAndNormalTexture->getRTV());
}

void SVGFShadowPass::computeReprojection(RenderContext* pRenderContext,
                                          Texture::SharedPtr pShadowTexture,
                                          Texture::SharedPtr pAoTexture,
                                          Texture::SharedPtr pMotionVectorAndFWidthTexture,
                                          Texture::SharedPtr pCurLinearZTexture,
                                          Texture::SharedPtr pPrevLinearZTexture)
{
  auto shaderVars = mpReprojection->getVars();

  shaderVars["gMotionAndFWidth"]        = pMotionVectorAndFWidthTexture;
  shaderVars["gShadow"]         = pShadowTexture;
  shaderVars["gAO"]         = pAoTexture;
  shaderVars["gPrevIllum"]     = mpFilteredPastFbo->getColorTexture(0);
  shaderVars["gPrevMoments"]   = mpPrevReprojFbo->getColorTexture(1);
  shaderVars["gLinearZAndNormal"]       = pCurLinearZTexture;
  shaderVars["gPrevLinearZAndNormal"]   = pPrevLinearZTexture;
  shaderVars["gPrevHistoryLength"] = mpPrevReprojFbo->getColorTexture(2);

  // Setup variables for our reprojection pass
  shaderVars["PerImageCB"]["gAlpha"] = mAlpha;
  shaderVars["PerImageCB"]["gMomentsAlpha"] = mMomentsAlpha;

  mpGfxState->setFbo(mpCurReprojFbo);
  mpReprojection->execute(pRenderContext, mpGfxState);
}

void SVGFShadowPass::computeFilteredMoments(RenderContext* pRenderContext, Texture::SharedPtr pCurLinearZTexture)
{
  auto shaderVars = mpFilterMoments->getVars();

  shaderVars["gIllumination"]     = mpCurReprojFbo->getColorTexture(0);
  shaderVars["gMoments"]          = mpCurReprojFbo->getColorTexture(1);
  shaderVars["gHistoryLength"]    = mpCurReprojFbo->getColorTexture(2);
  shaderVars["gLinearZAndNormal"]          = pCurLinearZTexture;

  shaderVars["PerImageCB"]["gPhiColor"]  = mPhiColor;
  shaderVars["PerImageCB"]["gPhiNormal"]  = mPhiNormal;

  mpGfxState->setFbo(mpPingPongFbo[0]);
  mpFilterMoments->execute(pRenderContext, mpGfxState);
}


void SVGFShadowPass::computeAtrousDecomposition(RenderContext* pRenderContext, Texture::SharedPtr pCurLinearZTexture)
{
  auto shaderVars = mpAtrous->getVars();
  shaderVars["gHistoryLength"] = mpCurReprojFbo->getColorTexture(2);
  shaderVars["gLinearZAndNormal"] = pCurLinearZTexture;
  shaderVars["PerImageCB"]["gPhiColor"]  = mPhiColor;
  shaderVars["PerImageCB"]["gPhiNormal"] = mPhiNormal;

  for (int i = 0; i < mFilterIterations; i++)
  {
    Fbo::SharedPtr curTargetFbo = mpPingPongFbo[1];
    shaderVars["gIllumination"] = mpPingPongFbo[0]->getColorTexture(0);
    shaderVars["PerImageCB"]["gStepSize"] = 1 << i;
    mpGfxState->setFbo(curTargetFbo);
    mpAtrous->execute(pRenderContext, mpGfxState);

    // store the filtered color for the feedback path
    if (i == std::min(mFeedbackTap, mFilterIterations - 1))
    {
        pRenderContext->blit(curTargetFbo->getColorTexture(0)->getSRV(), mpFilteredPastFbo->getRenderTargetView(0));
    }

    std::swap(mpPingPongFbo[0], mpPingPongFbo[1]);
  }

  if (mFeedbackTap < 0)
  {
    pRenderContext->blit(mpCurReprojFbo->getColorTexture(0)->getSRV(), mpFilteredPastFbo->getRenderTargetView(0));
  }
}