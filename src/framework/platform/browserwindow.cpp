/*
 * Copyright (c) 2024 OTArchive <https://otarchive.com>
 * Copyright (c) 2010-2014 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#ifdef __EMSCRIPTEN__

#include <framework/core/application.h>
#include "browserwindow.h"
#include <framework/core/eventdispatcher.h>
#include <framework/core/resourcemanager.h>
#include <framework/util/crypt.h>
#include "framework/core/graphicalapplication.h"
#include <framework/luaengine/luainterface.h>

#include <algorithm>
#include <cmath>

BrowserWindow& g_browserWindow = (BrowserWindow&)g_window;

// CODEX: celular/tablet = tela de toque sem mouse
static bool codexEhCelular() {
    // clang-format off
    return MAIN_THREAD_EM_ASM_INT({
        try {
            var toque = window.matchMedia && window.matchMedia("(pointer: coarse)").matches;
            var ua = /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent);
            return (toque || ua) ? 1 : 0;
        } catch (e) { return 0; }
    }) == 1;
    // clang-format on
}

static double codexPixelRatio() {
    // clang-format off
    return MAIN_THREAD_EM_ASM_DOUBLE({ return window.devicePixelRatio || 1; });
    // clang-format on
}

bool codexCelular() { return g_browserWindow.isCelular(); }

// CODEX: mostra/esconde o botao de teclado da pagina (no jogo o chat ja abre o teclado)
void codexBotaoTeclado(bool mostrar) {
    MAIN_THREAD_ASYNC_EM_ASM({
        var b = document.getElementById("codexTecladoBtn");
        if (b && window.CODEX_CELULAR) b.style.display = $0 ? "block" : "none";
        if (window.CODEX_CELULAR && window.codexModoJogo) window.codexModoJogo(!$0);
    }, mostrar ? 1 : 0);
}

// CODEX: botao de teclado do chat (no jogo o teclado so abre por ele)
// fundo = parte de baixo do campo, em pixels da interface
void codexTeclado(bool abrir, int fundo) {
    const double campoCss = fundo * g_browserWindow.getCssScale();
    MAIN_THREAD_ASYNC_EM_ASM({
        if (!window.CODEX_CELULAR) return;
        if ($0) { if (window.codexAbrirTeclado) window.codexAbrirTeclado($1, true); }
        else if (window.codexFecharTeclado) window.codexFecharTeclado();
    }, abrir ? 1 : 0, campoCss);
}

stdext::map<char, Fw::Key> m_keyMapStr;
EmscriptenWebGLContextAttributes attr;

BrowserWindow::BrowserWindow() {
    m_minimumSize = Size(600, 480);
    m_size = Size(1280, 720);
    m_running = false;
    web_keymap.push_back({ "Backspace", Fw::KeyBackspace });
    web_keymap.push_back({ "Tab", Fw::KeyTab });
    web_keymap.push_back({ "Enter", Fw::KeyEnter });
    web_keymap.push_back({ "ShiftLeft", Fw::KeyShift });
    web_keymap.push_back({ "ShiftRight", Fw::KeyShift });
    web_keymap.push_back({ "ControlLeft", Fw::KeyCtrl });
    web_keymap.push_back({ "ControlRight", Fw::KeyCtrl });
    web_keymap.push_back({ "AltLeft", Fw::KeyAlt });
    web_keymap.push_back({ "AltRight", Fw::KeyAlt });
    web_keymap.push_back({ "Pause", Fw::KeyPause });
    web_keymap.push_back({ "CapsLock", Fw::KeyCapsLock });
    web_keymap.push_back({ "Escape", Fw::KeyEscape });
    web_keymap.push_back({ "Space", Fw::KeySpace });
    web_keymap.push_back({ "PageUp", Fw::KeyPageUp });
    web_keymap.push_back({ "PageDown", Fw::KeyPageDown });
    web_keymap.push_back({ "End", Fw::KeyEnd });
    web_keymap.push_back({ "Home", Fw::KeyHome });
    web_keymap.push_back({ "ArrowLeft", Fw::KeyLeft });
    web_keymap.push_back({ "ArrowUp", Fw::KeyUp });
    web_keymap.push_back({ "ArrowRight", Fw::KeyRight });
    web_keymap.push_back({ "ArrowDown", Fw::KeyDown });
    web_keymap.push_back({ "PrintScreen", Fw::KeyPrintScreen });
    web_keymap.push_back({ "Insert", Fw::KeyInsert });
    web_keymap.push_back({ "Delete", Fw::KeyDelete });
    web_keymap.push_back({ "Digit0", Fw::Key0 });
    web_keymap.push_back({ "Digit1", Fw::Key1 });
    web_keymap.push_back({ "Digit2", Fw::Key2 });
    web_keymap.push_back({ "Digit3", Fw::Key3 });
    web_keymap.push_back({ "Digit4", Fw::Key4 });
    web_keymap.push_back({ "Digit5", Fw::Key5 });
    web_keymap.push_back({ "Digit6", Fw::Key6 });
    web_keymap.push_back({ "Digit7", Fw::Key7 });
    web_keymap.push_back({ "Digit8", Fw::Key8 });
    web_keymap.push_back({ "Digit9", Fw::Key9 });
    web_keymap.push_back({ "KeyA", Fw::KeyA });
    web_keymap.push_back({ "KeyB", Fw::KeyB });
    web_keymap.push_back({ "KeyC", Fw::KeyC });
    web_keymap.push_back({ "KeyD", Fw::KeyD });
    web_keymap.push_back({ "KeyE", Fw::KeyE });
    web_keymap.push_back({ "KeyF", Fw::KeyF });
    web_keymap.push_back({ "KeyG", Fw::KeyG });
    web_keymap.push_back({ "KeyH", Fw::KeyH });
    web_keymap.push_back({ "KeyI", Fw::KeyI });
    web_keymap.push_back({ "KeyJ", Fw::KeyJ });
    web_keymap.push_back({ "KeyK", Fw::KeyK });
    web_keymap.push_back({ "KeyL", Fw::KeyL });
    web_keymap.push_back({ "KeyM", Fw::KeyM });
    web_keymap.push_back({ "KeyN", Fw::KeyN });
    web_keymap.push_back({ "KeyO", Fw::KeyO });
    web_keymap.push_back({ "KeyP", Fw::KeyP });
    web_keymap.push_back({ "KeyQ", Fw::KeyQ });
    web_keymap.push_back({ "KeyR", Fw::KeyR });
    web_keymap.push_back({ "KeyS", Fw::KeyS });
    web_keymap.push_back({ "KeyT", Fw::KeyT });
    web_keymap.push_back({ "KeyU", Fw::KeyU });
    web_keymap.push_back({ "KeyV", Fw::KeyV });
    web_keymap.push_back({ "KeyW", Fw::KeyW });
    web_keymap.push_back({ "KeyX", Fw::KeyX });
    web_keymap.push_back({ "KeyY", Fw::KeyY });
    web_keymap.push_back({ "KeyZ", Fw::KeyZ });
    web_keymap.push_back({ "MetaLeft", Fw::KeyMeta });
    web_keymap.push_back({ "MetaRight", Fw::KeyMeta });
    web_keymap.push_back({ "Numpad1", Fw::KeyNumpad1 });
    web_keymap.push_back({ "Numpad2", Fw::KeyNumpad2 });
    web_keymap.push_back({ "Numpad3", Fw::KeyNumpad3 });
    web_keymap.push_back({ "Numpad4", Fw::KeyNumpad4 });
    web_keymap.push_back({ "Numpad5", Fw::KeyNumpad5 });
    web_keymap.push_back({ "Numpad6", Fw::KeyNumpad6 });
    web_keymap.push_back({ "Numpad7", Fw::KeyNumpad7 });
    web_keymap.push_back({ "Numpad8", Fw::KeyNumpad8 });
    web_keymap.push_back({ "Numpad9", Fw::KeyNumpad9 });
    web_keymap.push_back({ "Numpad0", Fw::KeyNumpad0 });
    web_keymap.push_back({ "NumpadMultiply", Fw::KeyAsterisk });
    web_keymap.push_back({ "NumpadAdd", Fw::KeyPlus });
    web_keymap.push_back({ "NumpadSubtract", Fw::KeyMinus });
    web_keymap.push_back({ "NumpadDecimal", Fw::KeyPeriod });
    web_keymap.push_back({ "NumpadDivide", Fw::KeySlash });
    web_keymap.push_back({ "F1", Fw::KeyF1 });
    web_keymap.push_back({ "F2", Fw::KeyF2 });
    web_keymap.push_back({ "F3", Fw::KeyF3 });
    web_keymap.push_back({ "F4", Fw::KeyF4 });
    web_keymap.push_back({ "F5", Fw::KeyF5 });
    web_keymap.push_back({ "F6", Fw::KeyF6 });
    web_keymap.push_back({ "F7", Fw::KeyF7 });
    web_keymap.push_back({ "F8", Fw::KeyF8 });
    web_keymap.push_back({ "F9", Fw::KeyF9 });
    web_keymap.push_back({ "F10", Fw::KeyF10 });
    web_keymap.push_back({ "F11", Fw::KeyF11 });
    web_keymap.push_back({ "F12", Fw::KeyF12 });
    web_keymap.push_back({ "NumLock", Fw::KeyNumLock });
    web_keymap.push_back({ "ScrollLock", Fw::KeyScrollLock });
    web_keymap.push_back({ "Semicolon", Fw::KeySemicolon });
    web_keymap.push_back({ "Equal", Fw::KeyEqual });
    web_keymap.push_back({ "Comma", Fw::KeyComma });
    web_keymap.push_back({ "Minus", Fw::KeyMinus });
    web_keymap.push_back({ "Period", Fw::KeyPeriod });
    web_keymap.push_back({ "Slash", Fw::KeySlash });
    web_keymap.push_back({ "Backquote", Fw::KeyGrave });
    web_keymap.push_back({ "BracketLeft", Fw::KeyLeftBracket });
    web_keymap.push_back({ "Backslash", Fw::KeyBackslash });
    web_keymap.push_back({ "BracketRight", Fw::KeyRightBracket });
    web_keymap.push_back({ "Quote", Fw::KeyQuote });
    web_keymap.push_back({ 0, Fw::KeyUnknown });
}

void BrowserWindow::terminate() {
    emscripten_set_mouseup_callback("#canvas", this, EM_TRUE, nullptr);
    emscripten_set_mousedown_callback("#canvas", this, EM_TRUE, nullptr);
    emscripten_set_wheel_callback("#canvas", this, EM_TRUE, nullptr);
    emscripten_set_mousemove_callback("#canvas", this, EM_TRUE, nullptr);
    emscripten_set_keydown_callback("#canvas", this, EM_TRUE, nullptr);
    emscripten_set_keyup_callback("#canvas", this, EM_TRUE, nullptr);
    emscripten_set_keypress_callback("#canvas", this, EM_TRUE, nullptr);
    emscripten_set_resize_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE, nullptr);
    emscripten_set_focus_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE, nullptr);
    emscripten_set_blur_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE, nullptr);
    emscripten_set_touchend_callback("#canvas", this, EM_TRUE, nullptr);
    emscripten_set_touchstart_callback("#canvas", this, EM_TRUE, nullptr);
    emscripten_set_touchmove_callback("#canvas", this, EM_TRUE, nullptr);
    emscripten_set_touchcancel_callback("#canvas", this, EM_TRUE, nullptr);
    EMSCRIPTEN_WEBGL_CONTEXT_HANDLE ctx = emscripten_webgl_get_current_context();
    emscripten_webgl_destroy_context(ctx);

    m_visible = false;
    m_running = false;
}

// CODEX: no celular desenha em resolucao real (nitido) e encolhe a interface
// para caber numa tela pequena; no computador fica tudo como antes.
void BrowserWindow::applyCanvasSize() {
    double w, h;
    emscripten_get_element_css_size("#canvas", &w, &h);
    if (w < 1) w = 1;
    if (h < 1) h = 1;

    if (m_celular) {
        m_pixelRatio = std::clamp<float>(static_cast<float>(codexPixelRatio()), 1.f, 2.f);
        if (h > w) {
            // em pe (so na tela de login): interface ~540 x 960, letras maiores
            m_cssScale = std::clamp<float>(static_cast<float>(std::min(w / 540.0, h / 960.0)), 0.45f, 1.f);
        } else {
            // deitado (jogo): area minima da interface do Codex ~1180 x 600
            m_cssScale = std::clamp<float>(static_cast<float>(std::min(w / 1180.0, h / 600.0)), 0.45f, 1.f);
        }
    } else {
        m_pixelRatio = 1.f;
        m_cssScale = 1.f;
    }

    const int pw = static_cast<int>(w * m_pixelRatio);
    const int ph = static_cast<int>(h * m_pixelRatio);
    emscripten_set_canvas_element_size("#canvas", pw, ph);
    glViewport(0, 0, pw, ph);
    m_size = Size(pw, ph);
    m_displayDensity = m_pixelRatio * m_cssScale;
}

void BrowserWindow::internalInitGL() {
    m_celular = codexEhCelular();
    double w, h;
    emscripten_get_element_css_size("#canvas", &w, &h);
    m_size = Size(int(w), int(h));
    emscripten_set_canvas_element_size("#canvas", int(w), int(h));


    EmscriptenWebGLContextAttributes attr;
    emscripten_webgl_init_context_attributes(&attr);
    attr.majorVersion = 2;
    attr.renderViaOffscreenBackBuffer = attr.explicitSwapControl = attr.alpha = attr.depth = attr.stencil = attr.antialias = attr.preserveDrawingBuffer = attr.failIfMajorPerformanceCaveat = 0;
    EMSCRIPTEN_WEBGL_CONTEXT_HANDLE ctx = emscripten_webgl_create_context("#canvas", &attr);
    emscripten_webgl_make_context_current(ctx);


    glViewport(0, 0, int(w), int(h));
    applyCanvasSize();
}

void BrowserWindow::poll() {
    if (!g_app.isRunning())
        return;


    if (!m_running) {
        m_visible = true;

        emscripten_set_mouseup_callback("#canvas", this, EM_TRUE, ([](int eventType, const EmscriptenMouseEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleMouseCallback(eventType, event);
            return EM_TRUE;
        }));
        emscripten_set_mousedown_callback("#canvas", this, EM_TRUE, ([](int eventType, const EmscriptenMouseEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleMouseCallback(eventType, event);
            return EM_TRUE;
        }));
        emscripten_set_wheel_callback("#canvas", this, EM_TRUE, ([](int eventType, const EmscriptenWheelEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleMouseWheelCallback(event);
            return EM_TRUE;
        }));
        emscripten_set_mousemove_callback("#canvas", this, EM_TRUE, ([](int eventType, const EmscriptenMouseEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleMouseMotionCallback(event);
            return EM_TRUE;
        }));
        emscripten_set_keydown_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE, ([](int eventType, const EmscriptenKeyboardEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleKeyboardCallback(eventType, event);
            return EM_TRUE;
        }));
        emscripten_set_keyup_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE, ([](int eventType, const EmscriptenKeyboardEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleKeyboardCallback(eventType, event);
            return EM_TRUE;
        }));
        emscripten_set_keypress_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE, ([](int eventType, const EmscriptenKeyboardEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleKeyboardCallback(eventType, event);
            return EM_TRUE;
        }));
        emscripten_set_resize_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE, ([](int eventType, const EmscriptenUiEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleResizeCallback(event);
            return EM_TRUE;
        }));
        emscripten_set_focus_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE, ([](int eventType, const EmscriptenFocusEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleFocusCallback(eventType, event);
            return EM_TRUE;
        }));
        emscripten_set_blur_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE, ([](int eventType, const EmscriptenFocusEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleFocusCallback(eventType, event);
            return EM_TRUE;
        }));
        emscripten_set_touchend_callback("#canvas", this, EM_TRUE, ([](int eventType, const EmscriptenTouchEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleTouchCallback(eventType, event);
            return EM_TRUE;
        }));
        emscripten_set_touchstart_callback("#canvas", this, EM_TRUE, ([](int eventType, const EmscriptenTouchEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleTouchCallback(eventType, event);
            return EM_TRUE;
        }));
        emscripten_set_touchmove_callback("#canvas", this, EM_TRUE, ([](int eventType, const EmscriptenTouchEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleTouchCallback(eventType, event);
            return EM_TRUE;
        }));
        emscripten_set_touchcancel_callback("#canvas", this, EM_TRUE, ([](int eventType, const EmscriptenTouchEvent* event, void* userData) -> EM_BOOL {
            static_cast<BrowserWindow*>(userData)->handleTouchCallback(eventType, event);
            return EM_TRUE;
        }));

        // clang-format off
        MAIN_THREAD_ASYNC_EM_ASM({
            document.addEventListener("paste", function(event){
                Module["ccall"]("paste_return", "number",["string", "number"],[event.clipboardData.getData("text/plain"), $0]);
            });
        }, this);
        MAIN_THREAD_ASYNC_EM_ASM({
            if (navigator && "virtualKeyboard" in navigator && (/iphone|ipod|ipad|android/i).test(navigator.userAgent)) {
                navigator.virtualKeyboard.overlaysContent = true;
                const textInput = document.getElementById("title-text");
                const DOM_VK_BACK_SPACE = 8;
                const DOM_VK_RETURN = 13;
                const DOM_ANDROID_CODE = 229; //https://stackoverflow.com/questions/36753548/keycode-on-android-is-always-229
                textInput.addEventListener("input", function(ev) {
                    textInput.innerHTML = "";
                    ev.preventDefault();
                    ev.stopPropagation();
                });
                textInput.addEventListener("keydown", function(ev) {
                    if (ev.which === DOM_VK_BACK_SPACE) {
                        const options = {
                            code: 'Backspace',
                            key : 'Backspace',
                            keyCode : DOM_VK_BACK_SPACE,
                            which : DOM_VK_BACK_SPACE
                        };
                        window.dispatchEvent(new KeyboardEvent('keydown', options));
                        window.dispatchEvent(new KeyboardEvent('keyup', options));
                        ev.preventDefault();
                        ev.stopPropagation();
                    }
                    if (ev.which === DOM_VK_RETURN) {
                        const options = {
                            charCode: DOM_VK_RETURN,
                            code : 'Enter',
                            key : 'Enter',
                            keyCode : DOM_VK_RETURN,
                            which : DOM_VK_RETURN
                        };
                        window.dispatchEvent(new KeyboardEvent('keydown', options));
                        window.dispatchEvent(new KeyboardEvent('keypress', options));
                        window.dispatchEvent(new KeyboardEvent('keyup', options));
                        ev.preventDefault();
                        ev.stopPropagation();
                    }
                    if (ev.which === DOM_ANDROID_CODE) {
                        ev.preventDefault();
                        ev.stopPropagation();
                    }
                });
                textInput.addEventListener("keyup", function(ev) {
                    if (ev.which === DOM_VK_BACK_SPACE || ev.which === DOM_VK_RETURN || ev.which === DOM_ANDROID_CODE) {
                        ev.preventDefault();
                        ev.stopPropagation();
                    }
                });
            }
        });
        // clang-format on

        m_onResize(m_size);
        m_running = true;
    }

    fireKeysPress();
}

extern "C" {
    //Called from javascript
    EMSCRIPTEN_KEEPALIVE inline int paste_return(char const* paste_data, void* callback_data) {
        static_cast<BrowserWindow*>(callback_data)->setClipboardText(paste_data);
        return 1;
    }
}

void BrowserWindow::handleMouseCallback(int eventType, const EmscriptenMouseEvent* mouseEvent) {
    if (!m_usingTouch && mouseEvent->screenX != 0 && mouseEvent->screenY != 0 && mouseEvent->clientX != 0 && mouseEvent->clientY != 0 && mouseEvent->targetX != 0 && mouseEvent->targetY != 0) {
        int button = mouseEvent->button;
        // CODEX: Ctrl/Shift/Alt vem junto com o clique (Ctrl+clique do controle classico)
        int mods = 0;
        if (mouseEvent->ctrlKey) mods |= Fw::KeyboardCtrlModifier | Fw::KeyboardPrimaryModifier;
        if (mouseEvent->shiftKey) mods |= Fw::KeyboardShiftModifier;
        if (mouseEvent->altKey) mods |= Fw::KeyboardAltModifier;
        if (mouseEvent->metaKey) mods |= Fw::KeyboardMetaModifier;
        g_dispatcher.addEvent([this, eventType, button, mods] {
            m_inputEvent.reset();
            m_inputEvent.keyboardModifiers = mods;
            m_inputEvent.type = (eventType == EMSCRIPTEN_EVENT_MOUSEDOWN) ? Fw::MousePressInputEvent : Fw::MouseReleaseInputEvent;
            switch (button) {
                case 0:
                    m_inputEvent.mouseButton = Fw::MouseLeftButton;
                    if (eventType == EMSCRIPTEN_EVENT_MOUSEDOWN) { m_mouseButtonStates |= 1 << Fw::MouseLeftButton; } else { g_dispatcher.addEvent([this] { m_mouseButtonStates &= ~(1 << Fw::MouseLeftButton); }); }
                    break;
                case 2:
                    m_inputEvent.mouseButton = Fw::MouseRightButton;
                    if (eventType == EMSCRIPTEN_EVENT_MOUSEDOWN) { m_mouseButtonStates |= 1 << Fw::MouseRightButton; } else { g_dispatcher.addEvent([this] { m_mouseButtonStates &= ~(1 << Fw::MouseRightButton); }); }
                    break;
                case 1:
                    m_inputEvent.mouseButton = Fw::MouseMidButton;
                    if (eventType == EMSCRIPTEN_EVENT_MOUSEDOWN) { m_mouseButtonStates |= 1 << Fw::MouseMidButton; } else { g_dispatcher.addEvent([this] { m_mouseButtonStates &= ~(1 << Fw::MouseMidButton); }); }
                    break;
                default:
                    m_inputEvent.type = Fw::NoInputEvent;
                    break;
            }
            if (m_inputEvent.type != Fw::NoInputEvent && m_onInputEvent)
                m_onInputEvent(m_inputEvent);
        });
    }
}

void BrowserWindow::handleMouseWheelCallback(const EmscriptenWheelEvent* event) {
    if (event->mouse.screenX != 0 && event->mouse.screenY != 0 && event->mouse.clientX != 0 && event->mouse.clientY != 0 && event->mouse.targetX != 0 && event->mouse.targetY != 0) {
        const bool descer = event->deltaY > 0;
        g_dispatcher.addEvent([this, descer] {
            m_inputEvent.reset();
            m_inputEvent.type = Fw::MouseReleaseInputEvent;
            descer ? m_inputEvent.wheelDirection = Fw::MouseWheelDown : m_inputEvent.wheelDirection = Fw::MouseWheelUp;
            m_inputEvent.type = Fw::MouseWheelInputEvent;
            m_inputEvent.mouseButton = Fw::MouseMidButton;
            if (m_inputEvent.type != Fw::NoInputEvent && m_onInputEvent)
                m_onInputEvent(m_inputEvent);
        });
    }
}


void BrowserWindow::handleResizeCallback(const EmscriptenUiEvent* event) {
    const Size antes = m_size;
    const float densAntes = m_displayDensity;
    applyCanvasSize();
    if (antes != m_size || densAntes != m_displayDensity)
        m_onResize(m_size);
}

void BrowserWindow::handleMouseMotionCallback(const EmscriptenMouseEvent* mouseEvent) {
    m_inputEvent.reset();
    m_inputEvent.type = Fw::MouseMoveInputEvent;
    Point newMousePos(mouseEvent->clientX / m_cssScale, mouseEvent->clientY / m_cssScale);
    m_inputEvent.mouseMoved = newMousePos - m_inputEvent.mousePos;
    m_inputEvent.mousePos = newMousePos;
    if (m_onInputEvent)
        m_onInputEvent(m_inputEvent);
}

// CODEX: toque reescrito.
//  - toque rapido            -> clique esquerdo (andar, usar botao)
//  - arrastar                -> segurar o botao esquerdo e mover (joystick, arrastar item, barra de rolagem)
//  - segurar parado ~0,45 s  -> clique direito (menu / usar)
// Os dados do navegador sao copiados na hora (o ponteiro do evento nao vale depois).
void BrowserWindow::handleTouchCallback(int eventType, const EmscriptenTouchEvent* event) {
    m_usingTouch = true;
    if (!event || event->numTouches <= 0)
        return;

    // cada dedo que mudou vira um evento (joystick + botao ao mesmo tempo)
    for (int i = 0; i < event->numTouches; ++i) {
        const EmscriptenTouchPoint* t = &event->touches[i];
        if (!t->isChanged)
            continue;
        const Point pos(static_cast<int>(t->targetX / m_cssScale), static_cast<int>(t->targetY / m_cssScale));
        const int id = t->identifier;
        g_dispatcher.addEvent([this, eventType, pos, id] { onTouch(eventType, pos, id); });
    }
}

// CODEX: o joystick do celular recebe o dedo direto (sem esperar arrastar e sem
// virar clique direito), por um dedo proprio. Lua: codexJoystickToque(tipo, x, y)
// tipo 0 = encostou (retorna true se o dedo e do joystick), 1 = moveu, 2 = soltou.
static bool codexJoystickToque(int tipo, const Point& pos) {
    bool usado = false;
    try {
        g_lua.getGlobal("codexJoystickToque");
        if (!g_lua.isFunction()) {
            g_lua.pop();
            return false;
        }
        g_lua.pushInteger(tipo);
        g_lua.pushInteger(pos.x);
        g_lua.pushInteger(pos.y);
        g_lua.safeCall(3, 1);
        usado = g_lua.popBoolean();
    } catch (...) {
        usado = false;
    }
    return usado;
}

void BrowserWindow::sendMouse(Fw::InputEventType type, Fw::MouseButton button, const Point& pos) {
    if (!m_onInputEvent)
        return;
    if (pos != m_inputEvent.mousePos) {
        m_inputEvent.reset();
        m_inputEvent.mouseMoved = pos - m_inputEvent.mousePos;
        m_inputEvent.mousePos = pos;
        m_inputEvent.type = Fw::MouseMoveInputEvent;
        m_onInputEvent(m_inputEvent);
    }
    if (type == Fw::MouseMoveInputEvent)
        return;

    m_inputEvent.reset();
    m_inputEvent.type = type;
    m_inputEvent.mouseButton = button;
    if (type == Fw::MousePressInputEvent)
        m_mouseButtonStates |= 1 << button;
    else
        m_mouseButtonStates &= ~(1 << button);
    m_onInputEvent(m_inputEvent);
}

void BrowserWindow::onTouch(int eventType, const Point& pos, int id) {
    static constexpr int DISTANCIA_ARRASTE = 10;
    static constexpr int TEMPO_SEGURAR = 450;

    if (eventType == EMSCRIPTEN_EVENT_TOUCHSTART && m_joyId < 0 && codexJoystickToque(0, pos)) {
        m_joyId = id;
        return;
    }
    if (id == m_joyId) {
        if (eventType == EMSCRIPTEN_EVENT_TOUCHMOVE) {
            codexJoystickToque(1, pos);
        } else if (eventType != EMSCRIPTEN_EVENT_TOUCHSTART) {
            m_joyId = -1;
            codexJoystickToque(2, pos);
        }
        return;
    }

    if (eventType == EMSCRIPTEN_EVENT_TOUCHSTART) {
        if (m_touchDown)
            return; // segundo dedo: ignorado
        m_touchDown = true;
        m_touchId = id;
        m_touchDragging = false;
        m_touchLong = false;
        m_touchStart = m_touchLast = pos;
        sendMouse(Fw::MouseMoveInputEvent, Fw::MouseLeftButton, pos);

        const int seq = ++m_touchSeq;
        g_dispatcher.scheduleEvent([this, seq] {
            if (!m_touchDown || seq != m_touchSeq || m_touchDragging || m_touchLong)
                return;
            m_touchLong = true;
            sendMouse(Fw::MousePressInputEvent, Fw::MouseRightButton, m_touchLast);
            sendMouse(Fw::MouseReleaseInputEvent, Fw::MouseRightButton, m_touchLast);
        }, TEMPO_SEGURAR);
        return;
    }

    if (!m_touchDown || id != m_touchId)
        return;

    m_touchLast = pos;

    if (eventType == EMSCRIPTEN_EVENT_TOUCHMOVE) {
        if (m_touchLong)
            return;
        if (!m_touchDragging) {
            const Point d = pos - m_touchStart;
            if (std::abs(d.x) + std::abs(d.y) < DISTANCIA_ARRASTE)
                return;
            m_touchDragging = true;
            sendMouse(Fw::MousePressInputEvent, Fw::MouseLeftButton, m_touchStart);
        }
        sendMouse(Fw::MouseMoveInputEvent, Fw::MouseLeftButton, pos);
        return;
    }

    // fim do toque (TOUCHEND ou TOUCHCANCEL)
    m_touchDown = false;
    m_touchId = -1;
    ++m_touchSeq;
    if (m_touchDragging) {
        sendMouse(Fw::MouseReleaseInputEvent, Fw::MouseLeftButton, pos);
    } else if (!m_touchLong && eventType == EMSCRIPTEN_EVENT_TOUCHEND) {
        sendMouse(Fw::MousePressInputEvent, Fw::MouseLeftButton, pos);
        sendMouse(Fw::MouseReleaseInputEvent, Fw::MouseLeftButton, pos);
    }
    m_touchDragging = false;
    m_touchLong = false;
}

void BrowserWindow::updateTouchPosition(const EmscriptenTouchEvent*) {}
void BrowserWindow::processLongTouch(const EmscriptenTouchEvent*) {}

size_t number_of_characters_in_utf8_string(const char* str) {
    if (!str) return 0;
    size_t num_chars = 0;
    while (*str) {
        if ((*str++ & 0xC0) != 0x80) ++num_chars; // Skip all continuation bytes
    }
    return num_chars;
}

bool  string_eq(const char* a, const char* b) {
    if (a == nullptr || b == nullptr) return false;
    return std::strcmp(a, b) == 0;
}

void BrowserWindow::handleKeyboardCallback(int eventType, const EmscriptenKeyboardEvent* keyboardEvent) {
    if (eventType == EMSCRIPTEN_EVENT_KEYPRESS) {
        if (m_onInputEvent && keyboardEvent->key[0] && number_of_characters_in_utf8_string(keyboardEvent->key) == 1) {
            m_inputEvent.reset(Fw::KeyTextInputEvent);
            m_inputEvent.keyText = keyboardEvent->key;
            m_onInputEvent(m_inputEvent);
        }
    }
    if (!keyboardEvent->repeat || eventType == EMSCRIPTEN_EVENT_KEYDOWN) {
        Fw::Key keyCode = Fw::KeyUnknown;
        for (size_t i = 0; i < web_keymap.size(); i++) {
            if (string_eq(web_keymap[i].first, keyboardEvent->code)) {
                keyCode = web_keymap[i].second;
                break;
            }
        }
        if (eventType == EMSCRIPTEN_EVENT_KEYDOWN)
            processKeyDown(keyCode);
        else if (eventType == EMSCRIPTEN_EVENT_KEYUP)
            processKeyUp(keyCode);
    }
}

void BrowserWindow::handleFocusCallback(int eventType, const EmscriptenFocusEvent* event) {
    releaseAllKeys();
    if (eventType == EMSCRIPTEN_EVENT_FOCUS) {
        m_focused = true;
    } else if (eventType == EMSCRIPTEN_EVENT_BLUR) {
        m_focused = false;
    }
}

void BrowserWindow::swapBuffers() {
    // emscripten_webgl_commit_frame(); // removed to improve performance (reduce CPU overhead)
}

void BrowserWindow::setVerticalSync(bool enable) {
}

std::string BrowserWindow::getClipboardText() {
    return m_clipboardText;
}

void BrowserWindow::setClipboardText(const std::string_view text) {
    m_clipboardText = text.data();
    std::string const& content = text.data();
    // clang-format off
    MAIN_THREAD_EM_ASM({
        navigator.clipboard.writeText(UTF8ToString($0));
    }, content.c_str());
    // clang-format on
}

Size BrowserWindow::getDisplaySize() {
    return m_size;
}

std::string BrowserWindow::getPlatformType() {
    return "BROWSER-WEBGL";
}

void BrowserWindow::init() {
    internalInitGL();
}

int BrowserWindow::loadMouseCursor(const std::string& file, const Point& hotSpot)
{
    const auto& path = g_resources.guessFilePath(file, "png");
    std::stringstream fin;
    g_resources.readFileStream(path, fin);
    std::string base64Image = g_crypt.base64Encode(fin.str());
    std::string cursor = "url(data:image/png;base64," + base64Image + ") " + std::to_string(hotSpot.x) + " " + std::to_string(hotSpot.y) + ", auto";

    m_cursors.push_back(cursor);
    return m_cursors.size() - 1;
}

void BrowserWindow::setMouseCursor(int cursorId) {
    if (cursorId >= (int)m_cursors.size() || cursorId < 0)
        return;
    // clang-format off
    MAIN_THREAD_ASYNC_EM_ASM({
        document.body.style.cursor = UTF8ToString($0);
    }, m_cursors[cursorId].c_str());
    // clang-format on
}

void BrowserWindow::restoreMouseCursor() {
    // clang-format off
    MAIN_THREAD_ASYNC_EM_ASM(
        document.body.style.cursor = "";
        );
    // clang-format on
}

/* Does not apply to Browser */
void BrowserWindow::resize(const Size& size) {}

void BrowserWindow::show() {}

void BrowserWindow::hide() {}

void BrowserWindow::maximize() {}

void BrowserWindow::move(const Point& pos) {}

void BrowserWindow::showMouse() {}

void BrowserWindow::hideMouse() {}

int BrowserWindow::internalLoadMouseCursor(const ImagePtr& image, const Point& hotSpot) { return 0; }

void BrowserWindow::setTitle(const std::string_view title) {}

void BrowserWindow::setMinimumSize(const Size& minimumSize) {}

void BrowserWindow::setFullscreen(bool fullscreen) {}

void BrowserWindow::setIcon(const std::string& iconFile) {}


#endif // __EMSCRIPTEN__
