/*
 * This file is part of Darling.
 *
 * Copyright (C) 2022 Darling developers
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */

#import <QuartzCore/CAMetalDrawable.h>
#import <Metal/MTLDrawableInternal.h>
#import <Metal/MTLTextureInternal.h>
#import <OpenGL/gl.h>
#import <OpenGL/OpenGL.h>

#if DARLING_METAL_ENABLED

#include <indium/indium.private.hpp>
#include <indium-kit/layer.hpp>

#include <atomic>
#include <functional>
#include <memory>

@class CAMetalLayerInternal;

// Whether the current GL context can import Vulkan semaphores (GL_EXT_semaphore_fd).
// Without it, the compositor waits on the CPU for a drawable's rendering to finish.
bool CAMetalDrawableGLImportsSemaphores();

// Logs once if the current GL context runs on another GPU than the Metal device.
void CAMetalDrawableWarnIfDisplayedOnAnotherDevice(const std::shared_ptr<Indium::PrivateDevice>& device);

class CAMetalDrawableTexture: public Indium::PrivateTexture {
	CGSize _size;
	VkImage _image = VK_NULL_HANDLE;
	VkDeviceMemory _memory = VK_NULL_HANDLE;
	VkImageView _imageView = VK_NULL_HANDLE;
	GLuint _textureID = 0;
	GLuint _memoryObject = 0;
	Indium::PixelFormat _pixelFormat;
	VkImage _internalImage = VK_NULL_HANDLE;
	VkDeviceMemory _internalMemory = VK_NULL_HANDLE;
	bool _framebufferOnly = false;
	bool _exportsSemaphore = true;

	void destroyVulkanObjects();

public:
	CAMetalDrawableTexture(CGSize size, Indium::PixelFormat pixelFormat, bool framebufferOnly, bool exportsSemaphore, std::shared_ptr<Indium::PrivateDevice> privateDevice);
	virtual ~CAMetalDrawableTexture();

	GLuint glTexture() const;

	// Blocks until all GPU work submitted so far that uses this texture has completed.
	// Returns false if the wait failed.
	bool waitForRendering();

	virtual VkImageView imageView() override;
	virtual VkImage image() override;
	virtual VkImageLayout imageLayout() override;
	virtual Indium::TextureType textureType() const override;
	virtual Indium::PixelFormat pixelFormat() const override;
	virtual size_t width() const override;
	virtual size_t height() const override;
	virtual size_t depth() const override;
	virtual size_t mipmapLevelCount() const override;
	virtual size_t arrayLength() const override;
	virtual size_t sampleCount() const override;
	virtual bool framebufferOnly() const override;
	virtual Indium::TextureUsage usage() const override;
	virtual bool allowGPUOptimizedContents() const override;
	virtual bool shareable() const override;
	virtual Indium::TextureSwizzleChannels swizzle() const override;
	virtual void replaceRegion(Indium::Region region, size_t mipmapLevel, const void* bytes, size_t bytesPerRow) override;
	virtual void replaceRegion(Indium::Region region, size_t mipmapLevel, size_t slice, const void* bytes, size_t bytesPerRow, size_t bytesPerImage) override;
	virtual void getBytes(Indium::Region region, size_t mipmapLevel, void* bytes, size_t bytesPerRow) override;
	virtual void getBytes(Indium::Region region, size_t mipmapLevel, size_t slice, void* bytes, size_t bytesPerRow, size_t bytesPerImage) override;

	virtual void precommit(std::shared_ptr<Indium::PrivateCommandBuffer> cmdbuf) override;
	virtual bool needsExportablePresentationSemaphore() const override;
};

// What -[CAMetalDrawableInternal] needs of the object behind a drawable, whichever way the
// layer presents: through its own images that the compositor copies from (CAMetalDrawableActual),
// or straight to a window through a swapchain (CAMetalSwapchainDrawable).
class CAMetalDrawableBase: public Indium::Drawable, public std::enable_shared_from_this<CAMetalDrawableBase> {
public:
	virtual ~CAMetalDrawableBase() {};

	virtual std::shared_ptr<Indium::Texture> indiumTexture() = 0;
	virtual NSUInteger drawableID() const = 0;
	virtual CFTimeInterval presentedTime() const = 0;

	// Called once, when present() is, before anything is presented.
	virtual void setWantsToPresentCallback(std::function<void()> wantsToPresentCallback) = 0;
	// Called once, after the drawable was shown or dropped.
	virtual void setDidPresentCallback(std::function<void()> didPresentCallback) = 0;

	// Marks the drawable as unused again (this has nothing to do with memory management).
	virtual void release() = 0;
	virtual void reset() = 0;
};

class CAMetalDrawableActual: public CAMetalDrawableBase {
private:
	std::shared_ptr<CAMetalDrawableTexture> _texture = nullptr;
	CAMetalLayerInternal* _layer = nil;
	std::shared_ptr<Indium::BinarySemaphore> _semaphore = nullptr;
	GLuint _glSemaphore = 0;
	std::function<void()> _wantsToPresentCallback = nullptr;
	std::function<void()> _didPresentCallback = nullptr;
	NSUInteger _drawableID = NSUIntegerMax;
	CFTimeInterval _presentedTime = 0;
	bool _queued = false;
	CGLContextObj _glContext = nullptr;
	bool _glImportsSemaphores = false;

	void waitForRenderingOnCPU();

public:
	CAMetalDrawableActual(CAMetalLayerInternal* layer, CGSize size, NSUInteger drawableID, Indium::PixelFormat pixelFormat, std::shared_ptr<Indium::Device> device, CGLContextObj _glContext, bool glImportsSemaphores);
	virtual ~CAMetalDrawableActual();

	virtual void present() override;

	std::shared_ptr<CAMetalDrawableTexture> texture();
	virtual std::shared_ptr<Indium::Texture> indiumTexture() override;
	virtual NSUInteger drawableID() const override;
	virtual CFTimeInterval presentedTime() const override;

	virtual void setWantsToPresentCallback(std::function<void()> wantsToPresentCallback) override;
	virtual void setDidPresentCallback(std::function<void()> didPresentCallback) override;

	void disown();

	void synchronizeRender();

	void didPresent();
	void didDrop();
	// this has nothing to do with memory management; this indicates that the drawable is no longer in use and can be recycled
	virtual void release() override;
	virtual void reset() override;
};

// A drawable of a layer that presents to its window through a Vulkan swapchain: the image
// belongs to the swapchain and presenting hands it to the presentation engine.
class CAMetalSwapchainDrawable: public CAMetalDrawableBase {
private:
	std::shared_ptr<IndiumKit::Drawable> _drawable;
	CAMetalLayerInternal* _layer = nil;
	NSUInteger _drawableID;
	std::atomic<CFTimeInterval> _presentedTime { 0 };
	std::function<void()> _wantsToPresentCallback = nullptr;
	std::function<void()> _didPresentCallback = nullptr;
	std::atomic<bool> _presentRequested { false };
	std::atomic<bool> _released { false };

public:
	CAMetalSwapchainDrawable(CAMetalLayerInternal* layer, std::shared_ptr<IndiumKit::Drawable> drawable, NSUInteger drawableID);
	virtual ~CAMetalSwapchainDrawable();

	virtual void present() override;

	virtual std::shared_ptr<Indium::Texture> indiumTexture() override;
	virtual NSUInteger drawableID() const override;
	virtual CFTimeInterval presentedTime() const override;

	virtual void setWantsToPresentCallback(std::function<void()> wantsToPresentCallback) override;
	virtual void setDidPresentCallback(std::function<void()> didPresentCallback) override;

	virtual void release() override;
	virtual void reset() override;
};
#endif

@interface CAMetalDrawableInternal : NSObject <CAMetalDrawable, MTLDrawableInternal>

#if DARLING_METAL_ENABLED
{
	NSUInteger _drawableID;
	CFTimeInterval _presentedTime;
	std::shared_ptr<CAMetalDrawableBase> _drawable;
	MTLTextureInternal* _texture;
	CAMetalLayer* _layer;
	NSMutableArray<MTLDrawablePresentedHandler>* _presentedHandlers;
}

- (instancetype)initWithLayer: (CAMetalLayer*)layer
                     drawable: (std::shared_ptr<CAMetalDrawableBase>)drawable;
#endif

@end
