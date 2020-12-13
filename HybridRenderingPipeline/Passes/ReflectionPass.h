#pragma once
#include "../SharedUtils/RenderPass.h"
#include "../SharedUtils/RayLaunch.h"

/** Ray traced ambient occlusion pass.
*/
class ReflectionPass : public ::RenderPass, inherit_shared_from_this<::RenderPass, ReflectionPass>
{
public:
    using SharedPtr = std::shared_ptr<ReflectionPass>;
    using SharedConstPtr = std::shared_ptr<const ReflectionPass>;

    static SharedPtr create(const std::string& channel) { return SharedPtr(new ReflectionPass(channel)); }
    virtual ~ReflectionPass() = default;

protected:
    ReflectionPass(const std::string& channel) : ::RenderPass("Reflection", "Reflection Options") {
        mAccumChannel = channel;
    }

    // Implementation of RenderPass interface
    bool initialize(RenderContext* pRenderContext, ResourceManager::SharedPtr pResManager) override;
    void initScene(RenderContext* pRenderContext, Scene::SharedPtr pScene) override;
    void execute(RenderContext* pRenderContext) override;
    void renderGui(Gui* pGui) override;

    // The RenderPass class defines various methods we can override to specify this pass' properties. 
    bool requiresScene() override { return true; }
    bool usesRayTracing() override { return true; }

    // Rendering state
    std::string                             mAccumChannel;
    RayLaunch::SharedPtr                    mpRays;                 ///< Our wrapper around a DX Raytracing pass
    RtScene::SharedPtr                      mpScene;                ///< Our scene file (passed in from app)  

    // Various internal parameters
    uint32_t                                mMinTSelector = 1;      ///< Allow user to select which minT value to use for rays
    uint32_t                                mFrameCount = 0;
    bool                                    mIsOpenScene = true;
    bool                                    mHalfResolution = false;
};
