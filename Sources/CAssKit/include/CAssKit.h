#ifndef CASSKIT_H
#define CASSKIT_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AssKitRendererRef AssKitRendererRef;

typedef struct AssKitRenderResult {
    int32_t changed;
    int32_t dirty_x;
    int32_t dirty_y;
    int32_t dirty_width;
    int32_t dirty_height;
    int32_t frame_width;
    int32_t frame_height;
    int32_t bytes_per_row;
    uint8_t *bgra;
    size_t bgra_count;
} AssKitRenderResult;

AssKitRendererRef *asskit_renderer_create(void);
void asskit_renderer_destroy(AssKitRendererRef *renderer);

int32_t asskit_renderer_set_frame_size(AssKitRendererRef *renderer, int32_t width, int32_t height);
void asskit_renderer_set_fonts_dir(AssKitRendererRef *renderer, const char *fonts_dir);
void asskit_renderer_set_fonts(AssKitRendererRef *renderer, const char *default_font, const char *default_family);

int32_t asskit_renderer_load_ass(AssKitRendererRef *renderer, const uint8_t *data, size_t count);
int32_t asskit_renderer_load_codec_private(AssKitRendererRef *renderer, const uint8_t *data, size_t count, int32_t check_read_order);
int32_t asskit_renderer_process_chunk(AssKitRendererRef *renderer, const uint8_t *data, size_t count, int64_t start_ms, int64_t duration_ms);
int32_t asskit_renderer_flush_track(AssKitRendererRef *renderer);
int32_t asskit_renderer_prune_events(AssKitRendererRef *renderer, int64_t deadline_ms);

AssKitRenderResult asskit_renderer_render(AssKitRendererRef *renderer, int64_t time_ms);
void asskit_render_result_free(AssKitRenderResult result);

#ifdef __cplusplus
}
#endif

#endif
