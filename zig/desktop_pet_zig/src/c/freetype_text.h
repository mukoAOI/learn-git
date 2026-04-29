#ifndef FREETYPE_TEXT_H
#define FREETYPE_TEXT_H

#ifdef __cplusplus
extern "C" {
#endif

int ft_text_init(const char *font_path, int pixel_height);
void ft_text_deinit(void);
void ft_draw_text(float x, float y, const unsigned char *text, int text_len, float scale, float r, float g, float b, float a);

#ifdef __cplusplus
}
#endif

#endif
