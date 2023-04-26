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

#define GL_GLEXT_PROTOTYPES 1

#import "CAMetalDrawableInternal.h"
#import "CAMetalLayerInternal.h"
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/MTLDeviceInternal.h>
#import <Metal/stubs.h>

#if DARLING_METAL_ENABLED

#include <OpenGL/gl.h>
#include <OpenGL/glext.h>
#include <indium/indium.private.hpp>

namespace DynamicVK = Indium::DynamicVK;

static void reportGLErrors(void) {
#if 0
	GLenum err;

	while ((err = glGetError()) != GL_NO_ERROR) {
		printf("*** OPENGL ERROR: %d ***\n", err);
	}
#endif
};

//
// dynamically imported
//

namespace Indium::DynamicVK {
	static DynamicFunction<PFN_vkGetSemaphoreFdKHR> vkGetSemaphoreFdKHR("vkGetSemaphoreFdKHR");
	static DynamicFunction<PFN_vkGetMemoryFdKHR> vkGetMemoryFdKHR("vkGetMemoryFdKHR");
};

//
// helper classes
//

// used to store a weak reference to an objc object within a C++ object (so it can be passed around in C++ code)
template<typename T>
class ObjcppWeakWrapper {
private:
	// needs to be mutable so we can use it in the copy constructor and the copy assignment operator.
	// plus, it's also modified externally, so it can never be truly const.
	mutable id _ref = nil;

public:
	ObjcppWeakWrapper() {};

	ObjcppWeakWrapper(T ref) {
		objc_storeWeak(&_ref, ref);
	};

	ObjcppWeakWrapper(const ObjcppWeakWrapper& other) {
		@autoreleasepool {
			objc_storeWeak(&_ref, objc_loadWeak(&other._ref));
		}
	};

	ObjcppWeakWrapper(ObjcppWeakWrapper&& other) {
		@autoreleasepool {
			objc_storeWeak(&_ref, objc_loadWeak(&other._ref));
			objc_storeWeak(&other._ref, nil);
		}
	};

	~ObjcppWeakWrapper() {
		objc_storeWeak(&_ref, nil);
	};

	ObjcppWeakWrapper& operator=(const ObjcppWeakWrapper& other) {
		@autoreleasepool {
			objc_storeWeak(&_ref, objc_loadWeak(&other._ref));
		}
		return *this;
	};

	ObjcppWeakWrapper& operator=(ObjcppWeakWrapper&& other) {
		@autoreleasepool {
			objc_storeWeak(&_ref, objc_loadWeak(&other._ref));
			objc_storeWeak(&other._ref, nil);
		}
		return *this;
	};

	operator T() const {
		return get();
	};

	T get() const {
		return objc_loadWeak(&_ref);
	};
};

//
// ideally, we would use a Vulkan surface + swapchain here to render directly to the screen.
// however, CALayers can also be rendered offscreen (e.g. with a CARenderer) and our current implementation of rendering
// in most places is to render to an OpenGL buffer (per window) and display that.
// plus, we don't have an easy way to get a surface here; we would need access to an X11 window/subwindow,
// which we don't have direct access to here (our delegate might). therefore, we follow suit
// with the existing CALayer implementation and just render to an image/texture.
//
// additionally, to avoid refactoring/reworking the existing CARenderer and CALayerContext code,
// we render to a Vulkan image with exportable memory that we can import into an OpenGL texture,
// along with a semaphore to synchronize the Vulkan rendering with OpenGL.
//

//
// texture
//

static size_t findSharedMemory(const VkMemoryRequirements& reqs, std::shared_ptr<Indium::PrivateDevice> device, bool framebufferOnly) {
	size_t targetIndex = SIZE_MAX;

	for (size_t i = 0; i < device->memoryProperties().memoryTypeCount; ++i) {
		const auto& type = device->memoryProperties().memoryTypes[i];

		if ((reqs.memoryTypeBits & (1 << i)) == 0) {
			continue;
		}

		if (!framebufferOnly && (type.propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) == 0) {
			continue;
		}

		if (!framebufferOnly && (type.propertyFlags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) == 0) {
			continue;
		}

		// okay, this is good enough
		targetIndex = i;
		break;
	}

	return targetIndex;
};

CAMetalDrawableTexture::CAMetalDrawableTexture(CGSize size, Indium::PixelFormat pixelFormat, bool framebufferOnly, std::shared_ptr<Indium::PrivateDevice> privateDevice):
	Indium::PrivateTexture(privateDevice),
	_size(size),
	_pixelFormat(pixelFormat),
	_framebufferOnly(framebufferOnly)
{
	//
	// create the images
	//

	// create the public Vulkan image
	VkImageCreateInfo imgInfo {};

	imgInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
	imgInfo.imageType = VK_IMAGE_TYPE_2D;
	imgInfo.format = Indium::pixelFormatToVkFormat(_pixelFormat);
	imgInfo.extent.width = _size.width;
	imgInfo.extent.height = _size.height;
	imgInfo.extent.depth = 1;
	imgInfo.mipLevels = 1;
	imgInfo.arrayLayers = 1;
	imgInfo.samples = VK_SAMPLE_COUNT_1_BIT;
	imgInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
	imgInfo.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
	imgInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
	imgInfo.queueFamilyIndexCount = 0;
	imgInfo.pQueueFamilyIndices = nullptr;
	imgInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

	if (DynamicVK::vkCreateImage(_device->device(), &imgInfo, nullptr, &_image) != VK_SUCCESS) {
		// TODO
		abort();
	}

	// now create the internal image (with exportable memory)
	imgInfo.format = VK_FORMAT_R8G8B8A8_UNORM;

	// some drivers (e.g. AMD's drivers) don't play nice when sharing
	// Vulkan images and OpenGL textures with optimal tiling
	// (https://gitlab.freedesktop.org/mesa/mesa/-/issues/7657)
	imgInfo.tiling = VK_IMAGE_TILING_LINEAR;

	VkExternalMemoryImageCreateInfo extMemInfo {};

	extMemInfo.sType = VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO;
	extMemInfo.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT;

	imgInfo.pNext = &extMemInfo;

	if (DynamicVK::vkCreateImage(_device->device(), &imgInfo, nullptr, &_internalImage) != VK_SUCCESS) {
		// TODO
		abort();
	}

	//
	// allocate some memory for the images
	//

	VkMemoryRequirements reqs {};

	// first, the public image

	DynamicVK::vkGetImageMemoryRequirements(_device->device(), _image, &reqs);

	size_t targetIndex = findSharedMemory(reqs, _device, _framebufferOnly);

	if (targetIndex == SIZE_MAX) {
		throw std::runtime_error("No suitable memory region found for image");
	}

	VkMemoryAllocateInfo allocInfo {};

	allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
	allocInfo.allocationSize = reqs.size;
	allocInfo.memoryTypeIndex = targetIndex;

	if (DynamicVK::vkAllocateMemory(_device->device(), &allocInfo, nullptr, &_memory) != VK_SUCCESS) {
		// TODO
		abort();
	}

	DynamicVK::vkBindImageMemory(_device->device(), _image, _memory, 0);

	// now, the internal image

	DynamicVK::vkGetImageMemoryRequirements(_device->device(), _internalImage, &reqs);

	targetIndex = findSharedMemory(reqs, _device, _framebufferOnly);

	if (targetIndex == SIZE_MAX) {
		throw std::runtime_error("No suitable memory region found for internal image");
	}

	VkExportMemoryAllocateInfo exportAllocInfo {};
	VkMemoryDedicatedAllocateInfo dedicatedInfo {};

	allocInfo.allocationSize = reqs.size;
	allocInfo.memoryTypeIndex = targetIndex;

	exportAllocInfo.sType = VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO;
	exportAllocInfo.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT;

	allocInfo.pNext = &exportAllocInfo;

	dedicatedInfo.sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO;
	dedicatedInfo.image = _internalImage;

	exportAllocInfo.pNext = &dedicatedInfo;

	if (DynamicVK::vkAllocateMemory(_device->device(), &allocInfo, nullptr, &_internalMemory) != VK_SUCCESS) {
		// TODO
		abort();
	}

	DynamicVK::vkBindImageMemory(_device->device(), _internalImage, _internalMemory, 0);

	//
	// transition the images into the general layout
	//

	VkCommandBufferAllocateInfo cmdBufAllocInfo {};
	cmdBufAllocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
	cmdBufAllocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
	cmdBufAllocInfo.commandPool = _device->oneshotCommandPool();
	cmdBufAllocInfo.commandBufferCount = 1;

	VkCommandBuffer cmdBuf;
	if (DynamicVK::vkAllocateCommandBuffers(_device->device(), &cmdBufAllocInfo, &cmdBuf) != VK_SUCCESS) {
		// TODO
		abort();
	}

	VkCommandBufferBeginInfo cmdBufBeginInfo {};
	cmdBufBeginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
	cmdBufBeginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

	DynamicVK::vkBeginCommandBuffer(cmdBuf, &cmdBufBeginInfo);

	VkImageMemoryBarrier barriers[2];

	barriers[0] = {};
	barriers[0].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
	barriers[0].srcAccessMask = VK_ACCESS_NONE;
	barriers[0].dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
	barriers[0].oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
	barriers[0].newLayout = VK_IMAGE_LAYOUT_GENERAL;
	barriers[0].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	barriers[0].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	barriers[0].image = _image;
	barriers[0].subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	barriers[0].subresourceRange.baseMipLevel = 0;
	barriers[0].subresourceRange.levelCount = 1;
	barriers[0].subresourceRange.baseArrayLayer = 0;
	barriers[0].subresourceRange.layerCount = 1;

	barriers[1] = barriers[0];
	barriers[1].image = _internalImage;

	DynamicVK::vkCmdPipelineBarrier(cmdBuf, VK_PIPELINE_STAGE_NONE, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, nullptr, 0, nullptr, sizeof(barriers) / sizeof(*barriers), barriers);

	DynamicVK::vkEndCommandBuffer(cmdBuf);

	VkFenceCreateInfo fenceCreateInfo {};
	fenceCreateInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;

	VkFence theFence = VK_NULL_HANDLE;

	if (DynamicVK::vkCreateFence(_device->device(), &fenceCreateInfo, nullptr, &theFence) != VK_SUCCESS) {
		// TODO
		abort();
	}

	VkSubmitInfo submitInfo {};
	submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
	submitInfo.commandBufferCount = 1;
	submitInfo.pCommandBuffers = &cmdBuf;

	DynamicVK::vkQueueSubmit(_device->graphicsQueue(), 1, &submitInfo, theFence);
	if (DynamicVK::vkWaitForFences(_device->device(), 1, &theFence, VK_TRUE, /* 1s */ 1ull * 1000 * 1000 * 1000) != VK_SUCCESS) {
		// TODO
		abort();
	}

	DynamicVK::vkDestroyFence(_device->device(), theFence, nullptr);

	DynamicVK::vkFreeCommandBuffers(_device->device(), _device->oneshotCommandPool(), 1, &cmdBuf);

	//
	// create an image view for the public image
	//

	VkImageViewCreateInfo imgViewInfo {};
	imgViewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
	imgViewInfo.image = _image;
	imgViewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
	imgViewInfo.format = Indium::pixelFormatToVkFormat(_pixelFormat);
	imgViewInfo.components.r = VK_COMPONENT_SWIZZLE_R;
	imgViewInfo.components.g = VK_COMPONENT_SWIZZLE_G;
	imgViewInfo.components.b = VK_COMPONENT_SWIZZLE_B;
	imgViewInfo.components.a = VK_COMPONENT_SWIZZLE_A;
	imgViewInfo.subresourceRange = barriers[0].subresourceRange;

	if (DynamicVK::vkCreateImageView(_device->device(), &imgViewInfo, nullptr, &_imageView) != VK_SUCCESS) {
		// TODO
		abort();
	}

	//
	// import the internal image into an OpenGL texture
	//

	// get an FD for the memory
	VkMemoryGetFdInfoKHR getFDInfo {};

	getFDInfo.sType = VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR;
	getFDInfo.memory = _internalMemory;
	getFDInfo.handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_FD_BIT;

	int fd = -1;

	if (DynamicVK::vkGetMemoryFdKHR(_device->device(), &getFDInfo, &fd) != VK_SUCCESS) {
		// TODO
		abort();
	}

	reportGLErrors();

	// import the memory into OpenGL
	glCreateMemoryObjectsEXT(1, &_memoryObject);
	reportGLErrors();

	// this transfers ownership of the FD to OpenGL
	glImportMemoryFdEXT(_memoryObject, reqs.size, GL_HANDLE_TYPE_OPAQUE_FD_EXT, fd);
	fd = -1;
	reportGLErrors();

	GLint prevTex = 0;
	glGetIntegerv(GL_TEXTURE_BINDING_2D, &prevTex);

	glCreateTextures(GL_TEXTURE_2D, 1, &_textureID);
	reportGLErrors();
	glTextureParameteri(_textureID, GL_TEXTURE_TILING_EXT, GL_LINEAR_TILING_EXT /*GL_OPTIMAL_TILING_EXT*/);
	glTextureParameteri(_textureID, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTextureParameteri(_textureID, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTextureParameteri(_textureID, GL_TEXTURE_WRAP_S, GL_REPEAT);
	glTextureParameteri(_textureID, GL_TEXTURE_WRAP_T, GL_REPEAT);
	reportGLErrors();

	glTextureStorageMem2DEXT(_textureID, 1, GL_RGBA8, _size.width, _size.height, _memoryObject, 0);
	reportGLErrors();

	glBindTexture(GL_TEXTURE_2D, prevTex);
};

CAMetalDrawableTexture::~CAMetalDrawableTexture() {
	reportGLErrors();
	glDeleteTextures(1, &_textureID);
	reportGLErrors();
	glDeleteMemoryObjectsEXT(1, &_memoryObject);
	reportGLErrors();

	DynamicVK::vkDestroyImageView(_device->device(), _imageView, nullptr);
	DynamicVK::vkDestroyImage(_device->device(), _image, nullptr);
	DynamicVK::vkFreeMemory(_device->device(), _memory, nullptr);
	DynamicVK::vkDestroyImage(_device->device(), _internalImage, nullptr);
	DynamicVK::vkFreeMemory(_device->device(), _internalMemory, nullptr);
};

GLuint CAMetalDrawableTexture::glTexture() const {
	return _textureID;
};

VkImageView CAMetalDrawableTexture::imageView() {
	return _imageView;
};

VkImage CAMetalDrawableTexture::image() {
	return _image;
};

VkImageLayout CAMetalDrawableTexture::imageLayout() {
	return VK_IMAGE_LAYOUT_GENERAL;
};

Indium::TextureType CAMetalDrawableTexture::textureType() const {
	return Indium::TextureType::e2D;
};

Indium::PixelFormat CAMetalDrawableTexture::pixelFormat() const {
	return _pixelFormat;
};

size_t CAMetalDrawableTexture::width() const {
	return _size.width;
};

size_t CAMetalDrawableTexture::height() const {
	return _size.height;
};

size_t CAMetalDrawableTexture::depth() const {
	return 1;
};

size_t CAMetalDrawableTexture::mipmapLevelCount() const {
	return 1;
};

size_t CAMetalDrawableTexture::arrayLength() const {
	return 1;
};

size_t CAMetalDrawableTexture::sampleCount() const {
	return 1;
};

bool CAMetalDrawableTexture::framebufferOnly() const {
	// TODO: determine this according to the layer
	return false;
};

bool CAMetalDrawableTexture::allowGPUOptimizedContents() const {
	return true;
};

bool CAMetalDrawableTexture::shareable() const {
	return false;
};

Indium::TextureSwizzleChannels CAMetalDrawableTexture::swizzle() const {
	return {};
};

void CAMetalDrawableTexture::replaceRegion(Indium::Region region, size_t mipmapLevel, const void* bytes, size_t bytesPerRow) {
	// TODO
	abort();
};

void CAMetalDrawableTexture::replaceRegion(Indium::Region region, size_t mipmapLevel, size_t slice, const void* bytes, size_t bytesPerRow, size_t bytesPerImage) {
	// TODO
	abort();
};

void CAMetalDrawableTexture::precommit(std::shared_ptr<Indium::PrivateCommandBuffer> cmdbuf) {
	// TODO: check if we need a barrier for the internal image as well; we probably do.
	//       we might even need a separate semaphore for it.

	VkImageMemoryBarrier barriers[2];

	barriers[0] = {};
	barriers[0].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
	barriers[0].srcAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
	barriers[0].dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
	barriers[0].oldLayout = VK_IMAGE_LAYOUT_GENERAL;
	barriers[0].newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
	barriers[0].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	barriers[0].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	barriers[0].image = _image;
	barriers[0].subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	barriers[0].subresourceRange.baseMipLevel = 0;
	barriers[0].subresourceRange.levelCount = 1;
	barriers[0].subresourceRange.baseArrayLayer = 0;
	barriers[0].subresourceRange.layerCount = 1;

	barriers[1] = barriers[0];
	barriers[1].dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
	barriers[1].newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
	barriers[1].image = _internalImage;

	DynamicVK::vkCmdPipelineBarrier(cmdbuf->commandBuffer(), VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, sizeof(barriers) / sizeof(*barriers), barriers);

	VkImageBlit region {};

	region.srcOffsets[0] = { 0, 0, 0 };
	region.srcOffsets[1] = { static_cast<int32_t>(width()), static_cast<int32_t>(height()), 1 };
	region.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	region.srcSubresource.mipLevel = 0;
	region.srcSubresource.baseArrayLayer = 0;
	region.srcSubresource.layerCount = 1;

	region.dstOffsets[0] = region.srcOffsets[0];
	region.dstOffsets[1] = region.srcOffsets[1];
	region.dstSubresource = region.srcSubresource;

	DynamicVK::vkCmdBlitImage(cmdbuf->commandBuffer(), _image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, _internalImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region, VK_FILTER_LINEAR);

	barriers[0].srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
	barriers[0].dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
	barriers[0].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
	barriers[0].newLayout = VK_IMAGE_LAYOUT_GENERAL;

	barriers[1].srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
	barriers[1].dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
	barriers[1].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
	barriers[1].newLayout = VK_IMAGE_LAYOUT_GENERAL;

	DynamicVK::vkCmdPipelineBarrier(cmdbuf->commandBuffer(), VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, sizeof(barriers) / sizeof(*barriers), barriers);
};

bool CAMetalDrawableTexture::needsExportablePresentationSemaphore() const {
	return true;
};

//
// drawable
//

CAMetalDrawableActual::CAMetalDrawableActual(CAMetalLayerInternal* layer, CGSize size, NSUInteger drawableID, Indium::PixelFormat pixelFormat, std::shared_ptr<Indium::Device> device, CGLContextObj glContext):
	_drawableID(drawableID),
	_glContext(CGLRetainContext(glContext))
{
	_texture = std::make_shared<CAMetalDrawableTexture>(size, pixelFormat, layer.framebufferOnly, std::dynamic_pointer_cast<Indium::PrivateDevice>(device));
	objc_storeWeak(&_layer, layer);
};

CAMetalDrawableActual::~CAMetalDrawableActual() {
	reset();
	objc_storeWeak(&_layer, nil);
	CGLReleaseContext(_glContext);
};

void CAMetalDrawableActual::present() {
	if (_queued) {
		if (_wantsToPresentCallback) {
			_wantsToPresentCallback();
			_wantsToPresentCallback = nullptr;
		}
		if (_didPresentCallback) {
			_didPresentCallback();
			_didPresentCallback = nullptr;
		}
		return;
	}

	_queued = true;

	if (_wantsToPresentCallback) {
		_wantsToPresentCallback();
		_wantsToPresentCallback = nullptr;
	}

	@autoreleasepool {
		CAMetalLayerInternal* layer = objc_loadWeak(&_layer);

		if (!layer) {
			// if we've been disowned, drop all presentation requests
			didDrop();
			return;
		}

		[layer queuePresent: _drawableID];

		_semaphore = _texture->synchronizePresentation();

		if (_semaphore) {
			int fd = -1;
			VkSemaphoreGetFdInfoKHR info {};

			info.sType = VK_STRUCTURE_TYPE_SEMAPHORE_GET_FD_INFO_KHR;
			info.semaphore = _semaphore->semaphore;
			info.handleType = VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_FD_BIT;

			if (DynamicVK::vkGetSemaphoreFdKHR(_semaphore->device->device(), &info, &fd) != VK_SUCCESS) {
				// TODO
				abort();
			}

			CGLContextObj prev = CGLGetCurrentContext();
			CGLSetCurrentContext(_glContext);

			reportGLErrors();
			glGenSemaphoresEXT(1, &_glSemaphore);
			reportGLErrors();
			glImportSemaphoreFdEXT(_glSemaphore, GL_HANDLE_TYPE_OPAQUE_FD_EXT, fd); // this consumes the FD
			fd = -1;
			reportGLErrors();

			CGLSetCurrentContext(prev);
		}
	}
}

std::shared_ptr<CAMetalDrawableTexture> CAMetalDrawableActual::texture() {
	return _texture;
};

NSUInteger CAMetalDrawableActual::drawableID() const {
	return _drawableID;
};

CFTimeInterval CAMetalDrawableActual::presentedTime() const {
	return _presentedTime;
};

void CAMetalDrawableActual::setWantsToPresentCallback(std::function<void()> wantsToPresentCallback) {
	_wantsToPresentCallback = wantsToPresentCallback;
};

void CAMetalDrawableActual::setDidPresentCallback(std::function<void()> didPresentCallback) {
	_didPresentCallback = didPresentCallback;
};

void CAMetalDrawableActual::disown() {
	objc_storeWeak(&_layer, nil);
};

void CAMetalDrawableActual::didPresent() {
	_presentedTime = CACurrentMediaTime();

	if (_didPresentCallback) {
		_didPresentCallback();
		_didPresentCallback = nullptr;
	}
};

void CAMetalDrawableActual::didDrop() {
	_presentedTime = 0;

	if (_didPresentCallback) {
		_didPresentCallback();
		_didPresentCallback = nullptr;
	}
};

void CAMetalDrawableActual::release() {
	@autoreleasepool {
		CAMetalLayerInternal* layer = objc_loadWeak(&_layer);
		[layer releaseDrawable: _drawableID];
	}
};

void CAMetalDrawableActual::reset() {
	if (_glSemaphore != 0) {
		reportGLErrors();
		glDeleteSemaphoresEXT(1, &_glSemaphore);
		_glSemaphore = 0;
		reportGLErrors();
	}

	_semaphore = nullptr;
	_wantsToPresentCallback = nullptr;
	_didPresentCallback = nullptr;
	_presentedTime = 0;
	_queued = false;
};

void CAMetalDrawableActual::synchronizeRender() {
	GLuint tex = _texture->glTexture();
	GLenum layout = GL_LAYOUT_GENERAL_EXT;
	glWaitSemaphoreEXT(_glSemaphore, 0, NULL, 1, &tex, &layout);
};

static void glDebugCallback(GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length, const GLchar* message, const void* context) {
	fprintf(stderr, "GL CALLBACK: %s type = 0x%x, severity = 0x%x, message = %s\n", (type == GL_DEBUG_TYPE_ERROR ? "** GL ERROR **" : ""), type, severity, message);
};

@implementation CAMetalDrawableInternal

@synthesize drawableID = _drawableID;
@synthesize presentedTime = _presentedTime;
@synthesize texture = _texture;
@synthesize layer = _layer;

#if 0
+ (void)initialize
{
	glEnable(GL_DEBUG_OUTPUT);
	glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
	glDebugMessageCallback(glDebugCallback, NULL);
}
#endif

- (instancetype)initWithLayer: (CAMetalLayer*)layer
                     drawable: (std::shared_ptr<CAMetalDrawableActual>)drawable
{
	self = [super init];
	if (self != nil) {
		_layer = [layer retain];
		_drawableID = drawable->drawableID();
		_presentedHandlers = [NSMutableArray new];
		_drawable = drawable;
		_texture = [[MTLTextureInternal alloc] initWithTexture: drawable->texture() device: layer.device resourceOptions: MTLResourceStorageModeShared];

		_drawable->reset();

		_drawable->setWantsToPresentCallback([weakSelf = ObjcppWeakWrapper(self)]() {
			@autoreleasepool {
				CAMetalDrawableInternal* me = weakSelf.get();

				if (!me) {
					return;
				}

				// ensure we stick around to see final presentation so we can notify _presentedHandlers
				// even if the user drops all their references to the drawable object
				//
				// once the wantsToPresentCallback is invoked (the one we're in right now),
				// it's guaranteed that the didPresentCallback will invoked (either for presentation
				// or for dropping), so we can be sure we're not leaking ourselves here.
				[me retain];
				me->_drawable->setDidPresentCallback([=]() {
					@autoreleasepool {
						// autorelease ourselves
						[me autorelease];

						me->_presentedTime = me->_drawable->presentedTime();

						// TODO: synchronize/lock this
						for (MTLDrawablePresentedHandler handler in me->_presentedHandlers) {
							handler(me);
						}

						// release the C++ drawable instance (and allow it to be recycled)
						me->_drawable->release();
						me->_drawable = nullptr;

						// XXX: it's not clear whether the texture is still accessible after presentation,
						//      but it *seems* that it would no longer be accessible. according to the documentation,
						//      you can safely retain a drawable to query certain properties such as drawableID and presentedTime,
						//      but no mention of texture is made.
						// TODO: verify this
						[me->_texture release];
						me->_texture = nil;
					}
				});
			}
		});
	}
	return self;
}

- (void)dealloc
{
	// explicitly release the drawable, in case it hasn't been released already.
	// this occurs when the drawable is requested (via nextDrawable from CAMetalLayer) but never presented.
	if (_drawable) {
		_drawable->release();
	}

	[_texture release];
	[_layer release];
	[_presentedHandlers release];

	[super dealloc];
}

- (void)present
{
	_drawable->present();
}

- (void)presentAfterMinimumDuration: (CFTimeInterval)duration
{
	// TODO
	abort();
}

- (void)presentAtTime: (CFTimeInterval)presentationTime
{
	// TODO
	abort();
}

- (void)addPresentedHandler: (MTLDrawablePresentedHandler)block
{
	[_presentedHandlers addObject: [[block copy] autorelease]];
}

- (std::shared_ptr<Indium::Drawable>)drawable
{
	return _drawable;
}

@end

#else

@implementation CAMetalDrawableInternal

@dynamic texture;
@dynamic layer;
@dynamic drawableID;
@dynamic presentedTime;

MTL_UNSUPPORTED_CLASS

@end

#endif
