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

#pragma once
#include "../SharedUtils/RenderPass.h"
#include "../SharedUtils/SimpleVars.h"
#include "../SharedUtils/FullscreenLaunch.h"

class ComparePass : public ::RenderPass, inherit_shared_from_this<::RenderPass, ComparePass>
{
public:
	using SharedPtr = std::shared_ptr<ComparePass>;
	using SharedConstPtr = std::shared_ptr<const ComparePass>;

	static SharedPtr create(const std::string &output) { return SharedPtr(new ComparePass(output)); }
	virtual ~ComparePass() = default;

protected:
	ComparePass(const std::string &output);

	// Implementation of SimpleRenderPass interface
	bool initialize(RenderContext* pRenderContext, ResourceManager::SharedPtr pResManager) override;
	void execute(RenderContext* pRenderContext) override;
	void renderGui(Gui* pGui) override;
	void resize(uint32_t width, uint32_t height) override;
    void pipelineUpdated(ResourceManager::SharedPtr pResManager) override;
	void updateDropdown(ResourceManager::SharedPtr pResManager);
	bool appliesPostprocess() override { return true; }

	// Information about the rendering texture we're accumulating into
	std::string       mOutputChannel;
	Gui::DropdownList mLeftBuffers;
	Gui::DropdownList mRightBuffers;  
	uint32_t          mSelectLeft = 0xFFFFFFFFu;
	uint32_t          mSelectRight = 0xFFFFFFFFu;
  
	// State for our accumulation shader
	FullscreenLaunch::SharedPtr   mpCompareShader;
	GraphicsState::SharedPtr      mpGfxState;
	Fbo::SharedPtr                mpInternalFbo;
};
