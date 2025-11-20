#import "GStreamerBackend.h"
#import "StreamingApp-Swift.h"
#include <gst/gst.h>
#include <gst/video/video.h>
#include <gst/app/gstappsink.h>
#include <gst/app/gstappsrc.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

GST_DEBUG_CATEGORY_STATIC(debug_category);
#define GST_CAT_DEFAULT debug_category

@interface GStreamerBackend()
-(void)setUIMessage:(gchar*)message;
-(void)app_function;
-(void)check_initialization_complete;
@end

@implementation GStreamerBackend {
    id ui_delegate;
    GstElement *pipeline;
    GstElement *video_sink;
    GstElement *appsrc_yolo;
    GstElement *app_sink;
    GMainContext *context;
    GMainLoop *main_loop;
    gboolean initialized;
    UIView *ui_video_view;
    Detector *detector;
    OverlayView *overlayView;
}

-(id)init:(id)uiDelegate videoView:(UIView *)video_view {
    if (self = [super init]) {
        self->ui_delegate = uiDelegate;
        self->ui_video_view = video_view;
        GST_DEBUG_CATEGORY_INIT(debug_category, "ios-gst", 0, "iOS GStreamer bridge");
        gst_debug_set_threshold_for_name("ios-gst", GST_LEVEL_DEBUG);
        gst_debug_set_colored(FALSE);
        detector = [Detector new];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self app_function];
            
        });
    }
    return self;
}

-(void)dealloc {
    if (pipeline) {
        GST_DEBUG("Setting the pipeline to NULL");
        gst_element_set_state(pipeline, GST_STATE_NULL);
        gst_object_unref(pipeline);
        pipeline = NULL;
    }
}

-(void)play {
    if (gst_element_set_state(pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE)
        [self setUIMessage:"Failed to set pipeline to playing"];
}

-(void)pause {
    if (gst_element_set_state(pipeline, GST_STATE_PAUSED) == GST_STATE_CHANGE_FAILURE)
        [self setUIMessage:"Failed to set pipeline to paused"];
}

-(void)setUIMessage:(gchar*)message {
    NSString *string = [NSString stringWithUTF8String:message];
    if (ui_delegate && [ui_delegate respondsToSelector:@selector(gstreamerSetUIMessage:)])
        [ui_delegate gstreamerSetUIMessage:string];
}

static void error_cb(GstBus *bus, GstMessage *msg, GStreamerBackend *self) {
    GError *err;
    gchar *debug_info;
    gst_message_parse_error(msg, &err, &debug_info);
    gchar *message_string = g_strdup_printf("Error from %s: %s", GST_OBJECT_NAME(msg->src), err->message);
    g_clear_error(&err);
    g_free(debug_info);
    [self setUIMessage:message_string];
    g_free(message_string);
    gst_element_set_state(self->pipeline, GST_STATE_NULL);
}

static void state_changed_cb(GstBus *bus, GstMessage *msg, GStreamerBackend *self) {
    GstState old_state, new_state, pending_state;
    gst_message_parse_state_changed(msg, &old_state, &new_state, &pending_state);
    if (GST_MESSAGE_SRC(msg) == GST_OBJECT(self->pipeline)) {
        gchar *message = g_strdup_printf("Pipeline state: %s", gst_element_state_get_name(new_state));
        [self setUIMessage:message];
        g_free(message);
    }
}

// Called whenever a new video frame arrives at the appsink
static GstFlowReturn on_new_sample(GstAppSink *sink, gpointer user_data) {
    GStreamerBackend *self = (__bridge GStreamerBackend *)user_data;
    GstSample *sample = gst_app_sink_pull_sample(sink);
    if (!sample) return GST_FLOW_OK;

    GstBuffer *buffer = gst_sample_get_buffer(sample);
    GstCaps *caps = gst_sample_get_caps(sample);
    GstStructure *s = gst_caps_get_structure(caps, 0);
    int width = 0, height = 0;
    gst_structure_get_int(s, "width", &width);
    gst_structure_get_int(s, "height", &height);

    GstMapInfo map;
    if (gst_buffer_map(buffer, &map, GST_MAP_READ)) {
        NSData *frame = [NSData dataWithBytes:map.data length:map.size];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSArray *detections = [self->detector detectRGBA:frame
                                                       width:width
                                                      height:height
                                                      stride:(width * 4)];

            // PRINTS: always log detection count (and first label if any)
            if (detections.count > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->overlayView updateDetections:detections];
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->overlayView clear];
                });
            }
        });


        gst_buffer_unmap(buffer, &map);
    }

    gst_sample_unref(sample);
    return GST_FLOW_OK;
}


-(void)check_initialization_complete {
    if (!initialized && main_loop) {
        if (ui_delegate && [ui_delegate respondsToSelector:@selector(gstreamerInitialized)])
            [ui_delegate gstreamerInitialized];
        initialized = TRUE;
    }
}

-(void)app_function {
    GstBus *bus;
    GSource *bus_source;
    GError *error = NULL;

    context = g_main_context_new();
    g_main_context_push_thread_default(context);

    const gchar *pipeline_str =
        /* CAMERA INPUT */
        "avfvideosrc ! video/x-raw,width=1280,height=720,framerate=30/1 ! "
        "videoconvert ! tee name=t "

        /* PREVIEW */
        "t. ! queue leaky=2 ! "
        "glimagesink name=videosink sync=false qos=false enable-last-sample=false "

        /* YOLO (Detection) */
        "t. ! queue leaky=2 ! "
        "videoscale ! video/x-raw,width=640,height=640 ! "
        "videoconvert ! video/x-raw,format=RGBA ! "
        "appsink name=app_sink emit-signals=true max-buffers=1 drop=true "

        /* SRT STREAMING */
        "t. ! queue leaky=2 ! "
        "videoconvert ! "
        "x264enc tune=zerolatency speed-preset=ultrafast key-int-max=30 bframes=0 byte-stream=true ! "
        "h264parse config-interval=1 ! "
        "mpegtsmux name=tsmux ! "
        "srtsink uri=\"srt://34.201.53.64:49001?mode=caller\" latency=1000 wait-for-connection=true "

        /* AUDIO for SRT */
        "autoaudiosrc ! queue ! "
        "audioconvert ! audioresample ! "
        "audio/x-raw,channels=2,rate=44100 ! "
        "voaacenc bitrate=128000 ! aacparse ! tsmux. "
;


    pipeline = gst_parse_launch(pipeline_str, &error);

    
    app_sink = gst_bin_get_by_name(GST_BIN(pipeline), "app_sink");
    if (app_sink) {
        g_object_set(app_sink, "emit-signals", TRUE, "max-buffers", 1, "drop", TRUE, NULL);
        g_signal_connect(app_sink, "new-sample", G_CALLBACK(on_new_sample), (__bridge void *)self);
    }


    if (error) {
        gchar *message = g_strdup_printf("Pipeline build error: %s", error->message);
        g_clear_error(&error);
        [self setUIMessage:message];
        g_free(message);
        return;
    }

    gst_element_set_state(pipeline, GST_STATE_READY);
    video_sink = gst_bin_get_by_interface(GST_BIN(pipeline), GST_TYPE_VIDEO_OVERLAY);
    if (video_sink) {
        gst_video_overlay_set_window_handle(GST_VIDEO_OVERLAY(video_sink), (guintptr)(id)ui_video_view);
    }

    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->overlayView) {
            self->overlayView = [[OverlayView alloc] initWithFrame:self->ui_video_view.bounds];
            self->overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

            // Make SURE it’s above any GL sublayers
            self->overlayView.layer.zPosition = 9999;

            // Faint tint so you can SEE the overlay exists
            self->overlayView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.03];

            [self->ui_video_view addSubview:self->overlayView];
        }
    });




    bus = gst_element_get_bus(pipeline);
    bus_source = gst_bus_create_watch(bus);
    g_source_set_callback(bus_source, (GSourceFunc)gst_bus_async_signal_func, NULL, NULL);
    g_source_attach(bus_source, context);
    g_source_unref(bus_source);

    g_signal_connect(G_OBJECT(bus), "message::error", (GCallback)error_cb, (__bridge void *)self);
    g_signal_connect(G_OBJECT(bus), "message::state-changed", (GCallback)state_changed_cb, (__bridge void *)self);
    gst_object_unref(bus);

    main_loop = g_main_loop_new(context, FALSE);
    [self check_initialization_complete];
    g_main_loop_run(main_loop);
    g_main_loop_unref(main_loop);
    main_loop = NULL;
    g_main_context_pop_thread_default(context);
    g_main_context_unref(context);
    gst_element_set_state(pipeline, GST_STATE_NULL);
    gst_object_unref(pipeline);
    return;
}

@end
