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

@class CAMetalLayerInternal;

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

public:
	CAMetalDrawableTexture(CGSize size, Indium::PixelFormat pixelFormat, bool framebufferOnly, std::shared_ptr<Indium::PrivateDevice> privateDevice);
	virtual ~CAMetalDrawableTexture();

	GLuint glTexture() const;

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
	virtual bool allowGPUOptimizedContents() const override;
	virtual bool shareable() const override;
	virtual Indium::TextureSwizzleChannels swizzle() const override;
	virtual void replaceRegion(Indium::Region region, size_t mipmapLevel, const void* bytes, size_t bytesPerRow) override;
	virtual void replaceRegion(Indium::Region region, size_t mipmapLevel, size_t slice, const void* bytes, size_t bytesPerRow, size_t bytesPerImage) override;

	virtual void precommit(std::shared_ptr<Indium::PrivateCommandBuffer> cmdbuf) override;
	virtual bool needsExportablePresentationSemaphore() const override;
};

class CAMetalDrawableActual: public Indium::Drawable {
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

public:
	CAMetalDrawableActual(CAMetalLayerInternal* layer, CGSize size, NSUInteger drawableID, Indium::PixelFormat pixelFormat, std::shared_ptr<Indium::Device> device, CGLContextObj _glContext);
	virtual ~CAMetalDrawableActual();

	virtual void present() override;

	std::shared_ptr<CAMetalDrawableTexture> texture();
	NSUInteger drawableID() const;
	CFTimeInterval presentedTime() const;

	void setWantsToPresentCallback(std::function<void()> wantsToPresentCallback);
	void setDidPresentCallback(std::function<void()> didPresentCallback);

	void disown();

	void synchronizeRender();

	void didPresent();
	void didDrop();
	// this has nothing to do with memory management; this indicates that the drawable is no longer in use and can be recycled
	void release();
	void reset();
};
#endif

@interface CAMetalDrawableInternal : NSObject <CAMetalDrawable, MTLDrawableInternal>

#if DARLING_METAL_ENABLED
{
	NSUInteger _drawableID;
	CFTimeInterval _presentedTime;
	std::shared_ptr<CAMetalDrawableActual> _drawable;
	MTLTextureInternal* _texture;
	CAMetalLayer* _layer;
	NSMutableArray<MTLDrawablePresentedHandler>* _presentedHandlers;
}

- (instancetype)initWithLayer: (CAMetalLayer*)layer
                     drawable: (std::shared_ptr<CAMetalDrawableActual>)drawable;
#endif

@end
