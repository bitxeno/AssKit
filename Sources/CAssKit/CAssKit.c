#include "CAssKit.h"

#include <ass/ass.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

struct AssKitRendererRef {
    ASS_Library *library;
    ASS_Renderer *renderer;
    ASS_Track *track;
    int32_t width;
    int32_t height;
    int32_t previous_x;
    int32_t previous_y;
    int32_t previous_width;
    int32_t previous_height;
};

static void asskit_message_callback(int level, const char *format, va_list args, void *data) {
    (void)level;
    (void)format;
    (void)args;
    (void)data;
}

static int32_t max_i32(int32_t a, int32_t b) { return a > b ? a : b; }
static int32_t min_i32(int32_t a, int32_t b) { return a < b ? a : b; }

static void union_rect(int32_t *x0, int32_t *y0, int32_t *x1, int32_t *y1,
                       int32_t x, int32_t y, int32_t width, int32_t height) {
    if (width <= 0 || height <= 0) {
        return;
    }
    if (*x1 <= *x0 || *y1 <= *y0) {
        *x0 = x;
        *y0 = y;
        *x1 = x + width;
        *y1 = y + height;
        return;
    }
    *x0 = min_i32(*x0, x);
    *y0 = min_i32(*y0, y);
    *x1 = max_i32(*x1, x + width);
    *y1 = max_i32(*y1, y + height);
}

static void blend_pixel(uint8_t *dst, uint8_t r, uint8_t g, uint8_t b, uint8_t alpha) {
    if (alpha == 0) {
        return;
    }

    uint32_t inv = 255u - alpha;
    dst[0] = (uint8_t)((b * alpha + dst[0] * inv) / 255u);
    dst[1] = (uint8_t)((g * alpha + dst[1] * inv) / 255u);
    dst[2] = (uint8_t)((r * alpha + dst[2] * inv) / 255u);
    dst[3] = (uint8_t)(alpha + (dst[3] * inv) / 255u);
}

static void reset_dirty_area(AssKitRendererRef *renderer) {
    renderer->previous_x = 0;
    renderer->previous_y = 0;
    renderer->previous_width = renderer->width;
    renderer->previous_height = renderer->height;
}

static void free_current_track(AssKitRendererRef *renderer) {
    if (renderer->track != NULL) {
        ass_free_track(renderer->track);
        renderer->track = NULL;
    }
}

AssKitRendererRef *asskit_renderer_create(void) {
    AssKitRendererRef *ref = (AssKitRendererRef *)calloc(1, sizeof(AssKitRendererRef));
    if (ref == NULL) {
        return NULL;
    }

    ref->library = ass_library_init();
    if (ref->library == NULL) {
        free(ref);
        return NULL;
    }

    ass_set_message_cb(ref->library, asskit_message_callback, NULL);
    ref->renderer = ass_renderer_init(ref->library);
    if (ref->renderer == NULL) {
        ass_library_done(ref->library);
        free(ref);
        return NULL;
    }

    ass_set_hinting(ref->renderer, ASS_HINTING_LIGHT);
    ass_set_fonts(ref->renderer, NULL, "Helvetica", 1, NULL, 1);
    return ref;
}

void asskit_renderer_destroy(AssKitRendererRef *renderer) {
    if (renderer == NULL) {
        return;
    }
    if (renderer->track != NULL) {
        ass_free_track(renderer->track);
    }
    if (renderer->renderer != NULL) {
        ass_renderer_done(renderer->renderer);
    }
    if (renderer->library != NULL) {
        ass_library_done(renderer->library);
    }
    free(renderer);
}

int32_t asskit_renderer_set_frame_size(AssKitRendererRef *renderer, int32_t width, int32_t height) {
    if (renderer == NULL || width <= 0 || height <= 0) {
        return -1;
    }
    if (renderer->width == width && renderer->height == height) {
        return 0;
    }
    renderer->width = width;
    renderer->height = height;
    reset_dirty_area(renderer);
    ass_set_frame_size(renderer->renderer, width, height);
    ass_set_storage_size(renderer->renderer, width, height);
    return 0;
}

void asskit_renderer_set_fonts_dir(AssKitRendererRef *renderer, const char *fonts_dir) {
    if (renderer == NULL) {
        return;
    }
    ass_set_fonts_dir(renderer->library, fonts_dir);
}

void asskit_renderer_set_fonts(AssKitRendererRef *renderer, const char *default_font, const char *default_family) {
    if (renderer == NULL) {
        return;
    }
    ass_set_fonts(renderer->renderer, default_font, default_family, 1, NULL, 1);
}

int32_t asskit_renderer_add_memory_font(AssKitRendererRef *renderer, const char *name, const uint8_t *data, size_t count) {
    if (renderer == NULL || renderer->library == NULL || name == NULL || data == NULL || count == 0 || count > INT32_MAX) {
        return -1;
    }

    ass_add_font(renderer->library, name, (const char *)data, (int)count);
    return 0;
}

int32_t asskit_renderer_load_ass(AssKitRendererRef *renderer, const uint8_t *data, size_t count) {
    if (renderer == NULL || data == NULL || count == 0) {
        return -1;
    }
    free_current_track(renderer);

    char *copy = (char *)malloc(count);
    if (copy == NULL) {
        return -2;
    }
    memcpy(copy, data, count);
    renderer->track = ass_read_memory(renderer->library, copy, count, NULL);
    free(copy);

    reset_dirty_area(renderer);
    return renderer->track == NULL ? -3 : 0;
}

int32_t asskit_renderer_load_codec_private(AssKitRendererRef *renderer, const uint8_t *data, size_t count, int32_t check_read_order) {
    if (renderer == NULL || data == NULL || count == 0 || count > INT32_MAX) {
        return -1;
    }

    free_current_track(renderer);
    renderer->track = ass_new_track(renderer->library);
    if (renderer->track == NULL) {
        return -2;
    }

    ass_process_codec_private(renderer->track, (const char *)data, (int)count);
    ass_set_check_readorder(renderer->track, check_read_order ? 1 : 0);
    reset_dirty_area(renderer);
    return 0;
}

int32_t asskit_renderer_process_chunk(AssKitRendererRef *renderer, const uint8_t *data, size_t count, int64_t start_ms, int64_t duration_ms) {
    if (renderer == NULL || renderer->track == NULL || data == NULL || count == 0 || count > INT32_MAX) {
        return -1;
    }
    if (start_ms < 0 || duration_ms < 0) {
        return -2;
    }

    ass_process_chunk(renderer->track, (const char *)data, (int)count, (long long)start_ms, (long long)duration_ms);
    reset_dirty_area(renderer);
    return 0;
}

int32_t asskit_renderer_flush_track(AssKitRendererRef *renderer) {
    if (renderer == NULL || renderer->track == NULL) {
        return -1;
    }
    ass_flush_events(renderer->track);
    reset_dirty_area(renderer);
    return 0;
}

int32_t asskit_renderer_prune_events(AssKitRendererRef *renderer, int64_t deadline_ms) {
    if (renderer == NULL || renderer->track == NULL || deadline_ms < 0) {
        return -1;
    }
    ass_prune_events(renderer->track, (long long)deadline_ms);
    reset_dirty_area(renderer);
    return 0;
}

AssKitRenderResult asskit_renderer_render(AssKitRendererRef *renderer, int64_t time_ms) {
    AssKitRenderResult result;
    memset(&result, 0, sizeof(result));

    if (renderer == NULL || renderer->track == NULL || renderer->width <= 0 || renderer->height <= 0) {
        result.changed = -1;
        return result;
    }

    int detect_change = 0;
    ASS_Image *images = ass_render_frame(renderer->renderer, renderer->track, (long long)time_ms, &detect_change);
    if (detect_change == 0) {
        result.changed = 0;
        return result;
    }

    int32_t current_x0 = 0;
    int32_t current_y0 = 0;
    int32_t current_x1 = 0;
    int32_t current_y1 = 0;

    for (ASS_Image *image = images; image != NULL; image = image->next) {
        int32_t x = max_i32(image->dst_x, 0);
        int32_t y = max_i32(image->dst_y, 0);
        int32_t x1 = min_i32(image->dst_x + image->w, renderer->width);
        int32_t y1 = min_i32(image->dst_y + image->h, renderer->height);
        union_rect(&current_x0, &current_y0, &current_x1, &current_y1, x, y, x1 - x, y1 - y);
    }

    int32_t dirty_x0 = current_x0;
    int32_t dirty_y0 = current_y0;
    int32_t dirty_x1 = current_x1;
    int32_t dirty_y1 = current_y1;
    union_rect(&dirty_x0, &dirty_y0, &dirty_x1, &dirty_y1,
               renderer->previous_x, renderer->previous_y,
               renderer->previous_width, renderer->previous_height);

    renderer->previous_x = current_x0;
    renderer->previous_y = current_y0;
    renderer->previous_width = max_i32(0, current_x1 - current_x0);
    renderer->previous_height = max_i32(0, current_y1 - current_y0);

    int32_t dirty_width = max_i32(0, dirty_x1 - dirty_x0);
    int32_t dirty_height = max_i32(0, dirty_y1 - dirty_y0);
    if (dirty_width == 0 || dirty_height == 0) {
        result.changed = 1;
        return result;
    }

    size_t bytes_per_row = (size_t)dirty_width * 4u;
    size_t count = bytes_per_row * (size_t)dirty_height;
    uint8_t *buffer = (uint8_t *)calloc(1, count);
    if (buffer == NULL) {
        result.changed = -2;
        return result;
    }

    for (ASS_Image *image = images; image != NULL; image = image->next) {
        uint8_t r = (uint8_t)((image->color >> 24) & 0xff);
        uint8_t g = (uint8_t)((image->color >> 16) & 0xff);
        uint8_t b = (uint8_t)((image->color >> 8) & 0xff);
        uint8_t color_alpha = (uint8_t)(255u - (image->color & 0xff));

        int32_t x_start = max_i32(image->dst_x, dirty_x0);
        int32_t y_start = max_i32(image->dst_y, dirty_y0);
        int32_t x_end = min_i32(image->dst_x + image->w, dirty_x1);
        int32_t y_end = min_i32(image->dst_y + image->h, dirty_y1);

        for (int32_t y = y_start; y < y_end; y++) {
            uint8_t *dst = buffer + (size_t)(y - dirty_y0) * bytes_per_row + (size_t)(x_start - dirty_x0) * 4u;
            uint8_t *src = image->bitmap + (size_t)(y - image->dst_y) * (size_t)image->stride + (size_t)(x_start - image->dst_x);
            for (int32_t x = x_start; x < x_end; x++) {
                uint8_t alpha = (uint8_t)(((uint32_t)(*src) * (uint32_t)color_alpha) / 255u);
                blend_pixel(dst, r, g, b, alpha);
                dst += 4;
                src += 1;
            }
        }
    }

    result.changed = 1;
    result.dirty_x = dirty_x0;
    result.dirty_y = dirty_y0;
    result.dirty_width = dirty_width;
    result.dirty_height = dirty_height;
    result.frame_width = renderer->width;
    result.frame_height = renderer->height;
    result.bytes_per_row = (int32_t)bytes_per_row;
    result.bgra = buffer;
    result.bgra_count = count;
    return result;
}

void asskit_render_result_free(AssKitRenderResult result) {
    if (result.bgra != NULL) {
        free(result.bgra);
    }
}
