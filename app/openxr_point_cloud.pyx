# distutils: language = c++
# distutils: sources = glad.c
# distutils: libraries = openxr_loader glfw3 opengl32 Open3D
# distutils: include_dirs = /path/to/openxr/include /path/to/glfw/include /path/to/open3d/include /path/to/glad/include
# distutils: library_dirs = /path/to/openxr/lib /path/to/glfw/lib /path/to/open3d/lib

cimport cython
from libcpp.vector cimport vector
from libcpp.string cimport string
from libcpp cimport bool
from libc.stdint cimport uint32_t
import numpy as np
cimport numpy as np

# OpenXR headers
cdef extern from "openxr/openxr.h":
    ctypedef struct XrInstance:
        pass
    ctypedef struct XrSession:
        pass
    ctypedef struct XrSystemId:
        pass
    ctypedef struct XrSpace:
        pass
    ctypedef struct XrFrameState:
        int64_t predictedDisplayTime
    ctypedef struct XrView:
        pass
    ctypedef enum XrResult:
        pass
    ctypedef enum XrSessionState:
        XR_SESSION_STATE_IDLE
        XR_SESSION_STATE_READY
        XR_SESSION_STATE_SYNCHRONIZED
        XR_SESSION_STATE_VISIBLE
        XR_SESSION_STATE_FOCUSED
        XR_SESSION_STATE_STOPPING
    XrResult xrCreateInstance(const XrInstanceCreateInfo* createInfo, XrInstance* instance)
    XrResult xrGetSystem(XrInstance instance, const XrSystemGetInfo* getInfo, XrSystemId* systemId)
    XrResult xrCreateSession(XrInstance instance, const XrSessionCreateInfo* createInfo, XrSession* session)
    XrResult xrCreateReferenceSpace(XrSession session, const XrReferenceSpaceCreateInfo* createInfo, XrSpace* space)
    XrResult xrPollEvent(XrInstance instance, XrEventDataBuffer* eventData)
    XrResult xrWaitFrame(XrSession session, const XrFrameWaitInfo* frameWaitInfo, XrFrameState* frameState)
    XrResult xrBeginFrame(XrSession session, const XrFrameBeginInfo* frameBeginInfo)
    XrResult xrEndFrame(XrSession session, const XrFrameEndInfo* frameEndInfo)
    XrResult xrLocateViews(XrSession session, const XrViewLocateInfo* viewLocateInfo, uint32_t* viewCountOutput, XrView* views)
    XrResult xrDestroySpace(XrSpace space)
    XrResult xrDestroySession(XrSession session)
    XrResult xrDestroyInstance(XrInstance instance)

cdef extern from "openxr/openxr_platform.h":
    ctypedef struct XrGraphicsBindingOpenGLWin32KHR:
        void* hDC
        void* hGLRC
    const char* XR_KHR_OPENGL_ENABLE_EXTENSION_NAME

# GLFW headers
cdef extern from "GLFW/glfw3.h":
    ctypedef struct GLFWwindow:
        pass
    void glfwInit()
    void glfwWindowHint(int hint, int value)
    GLFWwindow* glfwCreateWindow(int width, int height, const char* title, void* monitor, GLFWwindow* share)
    void glfwMakeContextCurrent(GLFWwindow* window)
    void glfwDestroyWindow(GLFWwindow* window)
    void glfwTerminate()
    void* glfwGetWin32Window(GLFWwindow* window)

# OpenGL headers (via GLAD)
cdef extern from "glad/glad.h":
    ctypedef unsigned int GLuint
    void glGenVertexArrays(GLuint n, GLuint* arrays)
    void glGenBuffers(GLuint n, GLuint* buffers)
    void glBindVertexArray(GLuint array)
    void glBindBuffer(GLuint target, GLuint buffer)
    void glBufferData(GLuint target, size_t size, const void* data, GLuint usage)
    void glVertexAttribPointer(GLuint index, int size, GLuint type, bool normalized, size_t stride, const void* pointer)
    void glEnableVertexAttribArray(GLuint index)
    void glClear(GLuint mask)
    void glDrawArrays(GLuint mode, int first, int count)
    void glDeleteVertexArrays(GLuint n, GLuint* arrays)
    void glDeleteBuffers(GLuint n, GLuint* buffers)
    GLuint glCreateShader(GLuint type)
    void glShaderSource(GLuint shader, int count, const char** string, const int* length)
    void glCompileShader(GLuint shader)
    GLuint glCreateProgram()
    void glAttachShader(GLuint program, GLuint shader)
    void glLinkProgram(GLuint program)
    void glUseProgram(GLuint program)
    void glDeleteShader(GLuint shader)
    void glDeleteProgram(GLuint program)
    void glUniformMatrix4fv(int location, int count, bool transpose, const float* value)
    int glGetUniformLocation(GLuint program, const char* name)
    unsigned int GL_ARRAY_BUFFER
    unsigned int GL_STATIC_DRAW
    unsigned int GL_POINTS
    unsigned int GL_VERTEX_SHADER
    unsigned int GL_FRAGMENT_SHADER
    unsigned int GL_COLOR_BUFFER_BIT
    unsigned int GL_DEPTH_BUFFER_BIT
    unsigned int GL_FLOAT
    bool gladLoadGL()

# Windows-specific for OpenGL context
cdef extern from "windows.h":
    void* GetDC(void* hWnd)
    void* wglGetCurrentContext()

# Open3D headers
cdef extern from "open3d/Open3D.h" namespace "open3d::io":
    ctypedef struct PointCloud:
        vector[vector[double]] points_
        vector[vector[double]] colors_
    PointCloud ReadPointCloud(const string& filename)

# GLM for matrix operations
cdef extern from "glm/glm.hpp" namespace "glm":
    ctypedef struct mat4:
        pass
    ctypedef struct vec3:
        pass
    mat4 perspective(float fovy, float aspect, float zNear, float zFar)
    mat4 translate(mat4 mat, vec3 v)

cdef extern from "glm/gtc/matrix_transform.hpp" namespace "glm":
    pass

# Error handling
cdef void check_xr(XrResult result, const char* msg) nogil:
    if result != 0:  # XR_SUCCESS
        with gil:
            raise RuntimeError(f"{msg}: {result}")

# Main rendering function
cpdef void render_point_cloud(str ply_file):
    cdef XrInstance instance
    cdef XrSession session
    cdef XrSystemId systemId
    cdef XrSpace referenceSpace
    cdef GLFWwindow* window
    cdef GLuint vao, vbo, shaderProgram

    # Initialize GLFW
    glfwInit()
    glfwWindowHint(0x22002, 0)  # GLFW_VISIBLE
    window = glfwCreateWindow(800, 600, "OpenXR Point Cloud", NULL, NULL)
    glfwMakeContextCurrent(window)
    gladLoadGL()

    # Initialize OpenXR
    cdef XrInstanceCreateInfo instanceInfo
    instanceInfo.type = 1000001000  # XR_TYPE_INSTANCE_CREATE_INFO
    instanceInfo.applicationInfo.apiVersion = (1 << 22) | (2 << 12)  # XR_CURRENT_API_VERSION
    strcpy(instanceInfo.applicationInfo.applicationName, "PointCloudVR")
    cdef const char* extensions[1]
    extensions[0] = XR_KHR_OPENGL_ENABLE_EXTENSION_NAME
    instanceInfo.enabledExtensionCount = 1
    instanceInfo.enabledExtensionNames = extensions
    check_xr(xrCreateInstance(&instanceInfo, &instance), "Failed to create XR instance")

    # Get system
    cdef XrSystemGetInfo systemInfo
    systemInfo.type = 1000004000  # XR_TYPE_SYSTEM_GET_INFO
    systemInfo.formFactor = 1  # XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY
    check_xr(xrGetSystem(instance, &systemInfo, &systemId), "Failed to get system")

    # Create session
    cdef XrGraphicsBindingOpenGLWin32KHR graphicsBinding
    graphicsBinding.type = 1000023000  # XR_TYPE_GRAPHICS_BINDING_OPENGL_WIN32_KHR
    graphicsBinding.hDC = GetDC(glfwGetWin32Window(window))
    graphicsBinding.hGLRC = wglGetCurrentContext()
    cdef XrSessionCreateInfo sessionInfo
    sessionInfo.type = 1000005000  # XR_TYPE_SESSION_CREATE_INFO
    sessionInfo.next = &graphicsBinding
    sessionInfo.systemId = systemId
    check_xr(xrCreateSession(instance, &sessionInfo, &session), "Failed to create session")

    # Create reference space
    cdef XrReferenceSpaceCreateInfo spaceInfo
    spaceInfo.type = 1000006000  # XR_TYPE_REFERENCE_SPACE_CREATE_INFO
    spaceInfo.referenceSpaceType = 1  # XR_REFERENCE_SPACE_TYPE_LOCAL
    check_xr(xrCreateReferenceSpace(session, &spaceInfo, &referenceSpace), "Failed to create reference space")

    # Load point cloud
    cdef PointCloud pcd = ReadPointCloud(ply_file.encode())
    cdef vector[float] vertexData
    for i in range(pcd.points_.size()):
        vertexData.push_back(pcd.points_[i][0])
        vertexData.push_back(pcd.points_[i][1])
        vertexData.push_back(pcd.points_[i][2])
        vertexData.push_back(pcd.colors_[i][0])
        vertexData.push_back(pcd.colors_[i][1])
        vertexData.push_back(pcd.colors_[i][2])

    # Set up OpenGL buffers
    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)
    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, vertexData.size() * sizeof(float), vertexData.data(), GL_STATIC_DRAW)
    glVertexAttribPointer(0, 3, GL_FLOAT, False, 6 * sizeof(float), <void*>0)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(1, 3, GL_FLOAT, False, 6 * sizeof(float), <void*>(3 * sizeof(float)))
    glEnableVertexAttribArray(1)
    glBindVertexArray(0)

    # Shaders
    cdef const char* vertexShaderSource = """
    #version 330 core
    layout(location = 0) in vec3 aPos;
    layout(location = 1) in vec3 aColor;
    out vec3 vColor;
    uniform mat4 mvp;
    void main() {
        gl_Position = mvp * vec4(aPos, 1.0);
        vColor = aColor;
        gl_PointSize = 2.0;
    }
    """
    cdef const char* fragmentShaderSource = """
    #version 330 core
    in vec3 vColor;
    out vec4 FragColor;
    void main() {
        FragColor = vec4(vColor, 1.0);
    }
    """

    # Compile shaders
    cdef GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER)
    glShaderSource(vertexShader, 1, &vertexShaderSource, NULL)
    glCompileShader(vertexShader)
    cdef GLuint fragmentShader = glCreateShader(GL_FRAGMENT_SHADER)
    glShaderSource(fragmentShader, 1, &fragmentShaderSource, NULL)
    glCompileShader(fragmentShader)
    shaderProgram = glCreateProgram()
    glAttachShader(shaderProgram, vertexShader)
    glAttachShader(shaderProgram, fragmentShader)
    glLinkProgram(shaderProgram)
    glDeleteShader(vertexShader)
    glDeleteShader(fragmentShader)

    # Render loop
    cdef XrSessionState state = XR_SESSION_STATE_IDLE
    cdef XrEventDataBuffer event
    event.type = 1000000000  # XR_TYPE_EVENT_DATA_BUFFER
    cdef bool running = True
    cdef XrFrameState frameState
    frameState.type = 1000002000  # XR_TYPE_FRAME_STATE
    cdef XrViewLocateInfo viewLocateInfo
    viewLocateInfo.type = 1000013000  # XR_TYPE_VIEW_LOCATE_INFO
    viewLocateInfo.viewConfigurationType = 2  # XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO
    viewLocateInfo.space = referenceSpace
    cdef uint32_t viewCount
    cdef XrView views[2]
    views[0].type = 1000003000  # XR_TYPE_VIEW
    views[1].type = 1000003000

    while running:
        # Poll events
        while xrPollEvent(instance, &event) == 0:
            if event.type == 1000007000:  # XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED
                state = (<XrEventDataSessionStateChanged*>&event).state
                if state == XR_SESSION_STATE_STOPPING:
                    running = False

        if state not in [XR_SESSION_STATE_READY, XR_SESSION_STATE_SYNCHRONIZED,
                         XR_SESSION_STATE_VISIBLE, XR_SESSION_STATE_FOCUSED]:
            continue

        # Frame handling
        cdef XrFrameWaitInfo waitInfo
        waitInfo.type = 1000009000  # XR_TYPE_FRAME_WAIT_INFO
        check_xr(xrWaitFrame(session, &waitInfo, &frameState), "Failed to wait frame")
        cdef XrFrameBeginInfo beginInfo
        beginInfo.type = 1000008000  # XR_TYPE_FRAME_BEGIN_INFO
        check_xr(xrBeginFrame(session, &beginInfo), "Failed to begin frame")

        # Locate views
        viewLocateInfo.displayTime = frameState.predictedDisplayTime
        check_xr(xrLocateViews(session, &viewLocateInfo, &viewCount, views), "Failed to locate views")

        # Render for each eye
        for i in range(viewCount):
            # Simplified projection (fovy approximated)
            cdef float fovy = 1.0  # Approximate from views[i].fov
            cdef mat4 projection = perspective(fovy, 1.0, 0.1, 100.0)
            cdef mat4 view = mat4(1.0)  # Simplified, use views[i].pose for accurate tracking
            cdef mat4 model = translate(mat4(1.0), vec3(0.0, 0.0, -2.0))
            cdef mat4 mvp = projection * view * model
            cdef float mvp_array[16]
            for j in range(16):
                mvp_array[j] = mvp[j / 4][j % 4]

            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
            glUseProgram(shaderProgram)
            glUniformMatrix4fv(glGetUniformLocation(shaderProgram, "mvp"), 1, False, mvp_array)
            glBindVertexArray(vao)
            glDrawArrays(GL_POINTS, 0, pcd.points_.size())
            glBindVertexArray(0)

        # End frame
        cdef XrFrameEndInfo endInfo
        endInfo.type = 1000010000  # XR_TYPE_FRAME_END_INFO
        endInfo.displayTime = frameState.predictedDisplayTime
        endInfo.environmentBlendMode = 1  # XR_ENVIRONMENT_BLEND_MODE_OPAQUE
        check_xr(xrEndFrame(session, &endInfo), "Failed to end frame")

    # Cleanup
    glDeleteVertexArrays(1, &vao)
    glDeleteBuffers(1, &vbo)
    glDeleteProgram(shaderProgram)
    xrDestroySpace(referenceSpace)
    xrDestroySession(session)
    xrDestroyInstance(instance)
    glfwDestroyWindow(window)
    glfwTerminate()