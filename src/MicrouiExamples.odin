package game

// Originally implemented by Oskar Nordquist at https://github.com/oskarnp
// Licence can be found here: https://github.com/oskarnp/microui-odin/blob/master/LICENSE

import "core:reflect"
import "core:strings"
import "core:fmt"

import mu "vendor:microui"

logbuf: strings.Builder;
logbuf_updated: bool;


uint8_slider :: proc(ctx: ^mu.Context, value: ^u8, low, high: int) -> (res: mu.Result_Set) {
    @static tmp: mu.Real;

    mu.push_id(ctx, uintptr(value));
    tmp = mu.Real(value^);
    res = mu.slider(ctx, &tmp, mu.Real(low), mu.Real(high), 0, "%.0f", {.ALIGN_CENTER});
    value^ = u8(tmp);
    mu.pop_id(ctx);

    return;
}

write_log :: proc(text: string) {
    strings.write_string(&logbuf, text);
    strings.write_string(&logbuf, "\n");
    logbuf_updated = true;
}

log_window :: proc(ctx: ^mu.Context) {
    if mu.begin_window(ctx, "Log Window", mu.Rect{350,40,300,200}) {
        /* output text panel */
        mu.layout_row(ctx, { -1 }, -28);
        mu.begin_panel(ctx, "Log Output");
        panel := mu.get_current_container(ctx);
        mu.layout_row(ctx, { -1 }, -1);
        mu.text(ctx, strings.to_string(logbuf));
        mu.end_panel(ctx);
        if logbuf_updated {
            panel.scroll.y = panel.content_size.y;
            logbuf_updated = false;
        }

        /* input textbox + submit button */
        @static textlen: int;
        @static textbuf: [128] byte;
        submitted := false;
        mu.layout_row(ctx, { -70, -1 }, 0);
        if .SUBMIT in mu.textbox(ctx, textbuf[:], &textlen) {
            mu.set_focus(ctx, ctx.last_id);
            submitted = true;
        }
        if mu.button(ctx, "Submit") != {} do submitted = true;
        if submitted {
            textstr := string(textbuf[:textlen]);

            write_log(textstr);

            textlen = 0;
        }

        mu.end_window(ctx);
    }
}

style_window :: proc(ctx: ^mu.Context) {
    if mu.begin_window(ctx, "Style Editor", mu.Rect{350,250,300,240}) {
        sw := i32(mu.Real(mu.get_current_container(ctx).body.w) * 0.14);
        mu.layout_row(ctx, { 95, sw, sw, sw, sw, -1 }, 0);
        for c in mu.Color_Type {
            mu.label(ctx, fmt.tprintf("%s:", reflect.enum_string(c)));
            uint8_slider(ctx, &ctx.style.colors[c].r, 0, 255);
            uint8_slider(ctx, &ctx.style.colors[c].g, 0, 255);
            uint8_slider(ctx, &ctx.style.colors[c].b, 0, 255);
            uint8_slider(ctx, &ctx.style.colors[c].a, 0, 255);
            mu.draw_rect(ctx, mu.layout_next(ctx), ctx.style.colors[c]);
        }
        mu.end_window(ctx);
    }
}

test_window :: proc(ctx: ^mu.Context) {
    @static opts: mu.Options;

    // NOTE(oskar): mu.button() returns Res_Bits and not bool (should fix this)
    button :: #force_inline proc(ctx: ^mu.Context, label: string) -> bool {
        return mu.button(ctx, label) == {.SUBMIT};
    }

    /* do window */
    if mu.begin_window(ctx, "Demo Window", {40,40,300,450}, opts) {
        if mu.header(ctx, "Window Options") != {} {
            win := mu.get_current_container(ctx);
            mu.layout_row(ctx, {120, 120, 120}, 0);
            for opt in mu.Opt {
                state: bool = opt in opts;
                if mu.checkbox(ctx, fmt.tprintf("%v", opt), &state) != {} {
                    if state {
                        opts |= {opt};
                    }
                    else {
                        opts &~= {opt};
                    }
                }
            }
        }

        /* window info */
        if mu.header(ctx, "Window Info") != {} {
            win := mu.get_current_container(ctx);
            mu.layout_row(ctx, { 54, -1 }, 0);
            mu.label(ctx, "Position:");
            mu.label(ctx, fmt.tprintf("%d, %d", win.rect.x, win.rect.y));
            mu.label(ctx, "Size:");
            mu.label(ctx, fmt.tprintf("%d, %d", win.rect.w, win.rect.h));
        }

        /* labels + buttons */
        if mu.header(ctx, "Test Buttons", {.EXPANDED}) != {} {
            mu.layout_row(ctx, { 86, -110, -1 }, 0);
            mu.label(ctx, "Test buttons 1:");
            if button(ctx, "Button 1") do write_log("Pressed button 1");
            if button(ctx, "Button 2") do write_log("Pressed button 2");
            mu.label(ctx, "Test buttons 2:");
            if button(ctx, "Button 3") do write_log("Pressed button 3");
            if button(ctx, "Button 4") do write_log("Pressed button 4");
        }

        /* tree */
        if mu.header(ctx, "Tree and Text", {.EXPANDED}) != {} {
            mu.layout_row(ctx, { 140, -1 }, 0);
            mu.layout_begin_column(ctx);
            if mu.begin_treenode(ctx, "Test 1") != {} {
                if mu.begin_treenode(ctx, "Test 1a") != {} {
                    mu.label(ctx, "Hello");
                    mu.label(ctx, "world");
                    mu.end_treenode(ctx);
                }
                if mu.begin_treenode(ctx, "Test 1b") != {} {
                    if button(ctx, "Button 1") do write_log("Pressed button 1");
                    if button(ctx, "Button 2") do write_log("Pressed button 2");
                    mu.end_treenode(ctx);
                }
                mu.end_treenode(ctx);
            }
            if mu.begin_treenode(ctx, "Test 2") != {} {
                mu.layout_row(ctx, { 54, 54 }, 0);
                if button(ctx, "Button 3") do write_log("Pressed button 3");
                if button(ctx, "Button 4") do write_log("Pressed button 4");
                if button(ctx, "Button 5") do write_log("Pressed button 5");
                if button(ctx, "Button 6") do write_log("Pressed button 6");
                mu.end_treenode(ctx);
            }
            if mu.begin_treenode(ctx, "Test 3") != {} {
                @static checks := [3]bool{ true, false, true };
                mu.checkbox(ctx, "Checkbox 1", &checks[0]);
                mu.checkbox(ctx, "Checkbox 2", &checks[1]);
                mu.checkbox(ctx, "Checkbox 3", &checks[2]);
                mu.end_treenode(ctx);
            }
            mu.layout_end_column(ctx);

            mu.layout_begin_column(ctx);
            mu.layout_row(ctx, { -1 }, 0);
            mu.text(ctx, "Lorem ipsum\n dolor sit amet, consectetur adipiscing elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus ipsum, eu varius magna felis a nulla.");
            mu.layout_end_column(ctx);
        }

        mu.end_window(ctx);
    }
}