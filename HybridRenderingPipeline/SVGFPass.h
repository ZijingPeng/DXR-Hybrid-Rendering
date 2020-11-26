// This class is to shading for the direct lighting

#pragma once
#include "../SharedUtils/RenderPass.h"
#include "../SharedUtils/FullscreenLaunch.h"

class SVGFPass : public ::RenderPass, inherit_shared_from_this<::RenderPass, SVGFPass>
{
public:
	using SharedPtr = std::shared_ptr<SVGFPass>;

	static SharedPtr create(const std::string& bufferToAccumulate = ResourceManager::kOutputChannel);
	virtual ~SVGFPass() = default;

protected:
	SVGFPass(const std::string& bufferToAccumulate);

	// Implementation of SimpleRenderPass interface
	bool initialize(RenderContext* pRenderContext, ResourceManager::SharedPtr pResManager) override;
	void initScene(RenderContext* pRenderContext, Scene::SharedPtr pScene) override;
	void execute(RenderContext* pRenderContext) override;
	void renderGui(Gui* pGui) override;
	void resize(uint32_t width, uint32_t height) override;

	// The RenderPass class defines various methods we can override to specify this pass' properties. 
	bool appliesPostprocess() override { return true; }
	void clearBuffers(RenderContext* pRenderContext);

	std::string                   mOutputTexName;

	// State for our shader
	FullscreenLaunch::SharedPtr   mpLambertShader;
	GraphicsState::SharedPtr      mpGfxState;
	Fbo::SharedPtr                mpInternalFbo;

	// We stash a copy of our current scene.  Why?  To detect if changes have occurred.
	Scene::SharedPtr              mpScene;

	// SVGF shaders
	FullscreenLaunch::SharedPtr   mpPackLinearZAndNormal;
	FullscreenLaunch::SharedPtr   mpReprojection;
	FullscreenLaunch::SharedPtr   mpAtrous;
	FullscreenLaunch::SharedPtr   mpFilterMoments;
	FullscreenLaunch::SharedPtr   mpFinalModulate;

	bool						  mBuffersNeedClear;
	bool					      mFilterEnabled;
};
