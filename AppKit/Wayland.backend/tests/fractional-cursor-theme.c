// Deterministic cursor pixels and hotspots for the private compositor fixture.
#include <X11/Xcursor/Xcursor.h>
#include <assert.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    const unsigned widths[] = {24, 30, 36, 42};
    XcursorImages *images = XcursorImagesCreate(4);
    assert(images);
    for (unsigned i = 0; i < 4; ++i) {
        unsigned width = widths[i], height = width * 2 / 3;
        XcursorImage *image = XcursorImageCreate(width, height);
        assert(image);
        image->size = width; image->xhot = width / 6; image->yhot = width / 3;
        for (unsigned j = 0; j < width * height; ++j) image->pixels[j] = 0xffff8000;
        images->images[i] = image; images->nimage = i + 1;
    }
    assert(XcursorFilenameSaveImages(argv[1], images));
    XcursorImagesDestroy(images);
    images = XcursorFilenameLoadAllImages(argv[1]);
    assert(images && images->nimage == 4);
    for (unsigned i = 0; i < 4; ++i) {
        XcursorImage *image = images->images[i];
        assert(image->width == widths[i] && image->height == widths[i] * 2 / 3);
        assert(image->xhot == widths[i] / 6 && image->yhot == widths[i] / 3);
        for (unsigned j = 0; j < image->width * image->height; ++j) assert(image->pixels[j] == 0xffff8000);
    }
    XcursorImagesDestroy(images);
    puts("Synthetic cursor theme: four exact images and hotspots verified");
}
