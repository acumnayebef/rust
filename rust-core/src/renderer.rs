use std::ffi::c_void;
use std::mem::size_of;

use bytemuck::{Pod, Zeroable};
use glam::{Mat4, Vec3};

const DEPTH_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Depth32Float;

const VOXEL_SHADER_WGSL: &str = r#"
struct CameraUniform {
    view_proj: mat4x4<f32>,
    sun_dir: vec4<f32>,
    fog_color: vec4<f32>,
    camera_pos: vec4<f32>,
    params: vec4<f32>,
};

@group(0) @binding(0)
var<uniform> u_camera: CameraUniform;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) color: vec3<f32>,
    @location(2) normal: vec3<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) world_pos: vec3<f32>,
};

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = u_camera.view_proj * vec4<f32>(in.position, 1.0);
    out.color = in.color;
    out.normal = in.normal;
    out.world_pos = in.position;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let n = normalize(in.normal);
    let sun = normalize(u_camera.sun_dir.xyz);
    let ndotl = max(dot(n, sun), 0.0);

    let shader_boost = u_camera.params.y;
    let ambient = 0.34 + 0.08 * max(n.y, 0.0);
    let warm_tint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.12, 1.03, 0.90), shader_boost);
    let sky_fill = max(-n.y * 0.1 + 0.12, 0.0) * vec3<f32>(0.55, 0.72, 0.95);

    var lit = in.color * (ambient + ndotl * (0.72 + 0.25 * shader_boost)) * warm_tint;
    lit = lit + in.color * sky_fill * shader_boost;

    let dist = length(in.world_pos - u_camera.camera_pos.xyz);
    let fog_start = 18.0;
    let fog_end = 42.0;
    let fog_factor = clamp((dist - fog_start) / (fog_end - fog_start), 0.0, 0.75);
    let final_rgb = mix(lit, u_camera.fog_color.rgb, fog_factor);

    return vec4<f32>(final_rgb, 1.0);
}
"#;

#[repr(C)]
#[derive(Copy, Clone, Debug, Pod, Zeroable)]
struct Vertex {
    position: [f32; 3],
    color: [f32; 3],
    normal: [f32; 3],
}

impl Vertex {
    const LAYOUT: wgpu::VertexBufferLayout<'static> = wgpu::VertexBufferLayout {
        array_stride: size_of::<Vertex>() as wgpu::BufferAddress,
        step_mode: wgpu::VertexStepMode::Vertex,
        attributes: &[
            wgpu::VertexAttribute {
                offset: 0,
                shader_location: 0,
                format: wgpu::VertexFormat::Float32x3,
            },
            wgpu::VertexAttribute {
                offset: size_of::<[f32; 3]>() as wgpu::BufferAddress,
                shader_location: 1,
                format: wgpu::VertexFormat::Float32x3,
            },
            wgpu::VertexAttribute {
                offset: (size_of::<[f32; 3]>() * 2) as wgpu::BufferAddress,
                shader_location: 2,
                format: wgpu::VertexFormat::Float32x3,
            },
        ],
    };
}

#[repr(C)]
#[derive(Copy, Clone, Debug, Pod, Zeroable)]
struct CameraUniform {
    view_proj: [[f32; 4]; 4],
    sun_dir: [f32; 4],
    fog_color: [f32; 4],
    camera_pos: [f32; 4],
    params: [f32; 4],
}

/// Accumulated touch and virtual D-pad input state.
#[derive(Debug, Clone, Copy, Default)]
pub struct InputState {
    pub move_x: f32,
    pub move_y: f32,
    pub look_dx: f32,
    pub look_dy: f32,
    pub jump_requested: bool,
}

/// First-person camera state inside the procedural Rust voxel world.
#[derive(Debug, Clone)]
pub struct CameraState {
    pub position: Vec3,
    pub yaw: f32,
    pub pitch: f32,
    pub vy: f32,
}

impl Default for CameraState {
    fn default() -> Self {
        Self {
            position: Vec3::new(0.0, 9.5, 14.0),
            yaw: -std::f32::consts::FRAC_PI_2,
            pitch: -0.32,
            vy: 0.0,
        }
    }
}

impl CameraState {
    pub fn update(&mut self, dt: f32, input: &mut InputState) {
        let sensitivity = 0.0065;
        self.yaw += input.look_dx * sensitivity;
        self.pitch = (self.pitch - input.look_dy * sensitivity).clamp(-1.35, 1.35);
        input.look_dx = 0.0;
        input.look_dy = 0.0;

        let forward = Vec3::new(self.yaw.cos(), 0.0, self.yaw.sin()).normalize_or_zero();
        let right = Vec3::new(-forward.z, 0.0, forward.x);

        let speed = 6.5;
        let wish = forward * input.move_y + right * input.move_x;
        self.position += wish * speed * dt;

        // Decay D-pad step impulse smoothly so discrete button taps feel responsive.
        let decay = (1.0 - dt * 6.0).max(0.0);
        input.move_x *= decay;
        input.move_y *= decay;

        if input.jump_requested && self.position.y <= 9.6 {
            self.vy = 6.5;
        }
        input.jump_requested = false;

        self.vy -= 18.0 * dt;
        self.position.y += self.vy * dt;
        if self.position.y < 9.5 {
            self.position.y = 9.5;
            self.vy = 0.0;
        }
    }

    pub fn view_proj(&self, aspect: f32) -> Mat4 {
        let dir = Vec3::new(
            self.yaw.cos() * self.pitch.cos(),
            self.pitch.sin(),
            self.yaw.sin() * self.pitch.cos(),
        )
        .normalize();

        let view = Mat4::look_to_rh(self.position, dir, Vec3::Y);
        let proj = Mat4::perspective_rh(65_f32.to_radians(), aspect.max(0.1), 0.1, 160.0);
        proj * view
    }
}

/// Real `wgpu` Metal 3D voxel renderer attached to iOS `CAMetalLayer`.
pub struct VoxelRenderer {
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    pipeline: wgpu::RenderPipeline,
    vertex_buffer: wgpu::Buffer,
    index_buffer: wgpu::Buffer,
    index_count: u32,
    uniform_buffer: wgpu::Buffer,
    uniform_bind_group: wgpu::BindGroup,
    depth_view: wgpu::TextureView,
    shader_boost: f32,
}

impl VoxelRenderer {
    /// Creates the `wgpu` Metal surface and rendering pipeline from a `CAMetalLayer` pointer.
    ///
    /// # Safety
    /// `metal_layer_ptr` must be a valid non-null pointer to an iOS `CAMetalLayer` that outlives
    /// the returned `VoxelRenderer`.
    pub unsafe fn new(
        metal_layer_ptr: usize,
        width: u32,
        height: u32,
        vsync: bool,
        shader_enabled: bool,
        shader_quality: &str,
    ) -> Result<Self, String> {
        if metal_layer_ptr == 0 {
            return Err("CAMetalLayer pointer is null".to_string());
        }

        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::METAL,
            ..Default::default()
        });

        #[cfg(any(target_os = "ios", target_os = "macos"))]
        let surface = instance
            .create_surface_unsafe(wgpu::SurfaceTargetUnsafe::CoreAnimationLayer(
                metal_layer_ptr as *mut c_void,
            ))
            .map_err(|e| format!("create_surface_unsafe failed: {e}"))?;

        #[cfg(not(any(target_os = "ios", target_os = "macos")))]
        {
            let _ = instance;
            return Err("CoreAnimationLayer rendering is only available on Apple targets".to_string());
        }

        #[cfg(any(target_os = "ios", target_os = "macos"))]
        {
            let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                compatible_surface: Some(&surface),
                force_fallback_adapter: false,
            }))
            .ok_or_else(|| "No compatible Metal GPU adapter found".to_string())?;

            let (device, queue) = pollster::block_on(adapter.request_device(
                &wgpu::DeviceDescriptor {
                    label: Some("mc_rust_metal_device"),
                    required_features: wgpu::Features::empty(),
                    required_limits: wgpu::Limits::downlevel_defaults(),
                    memory_hints: wgpu::MemoryHints::Performance,
                },
                None,
            ))
            .map_err(|e| format!("request_device failed: {e}"))?;

            let caps = surface.get_capabilities(&adapter);
            let format = caps
                .formats
                .iter()
                .copied()
                .find(|f| f.is_srgb())
                .or_else(|| caps.formats.first().copied())
                .ok_or_else(|| "Surface reported zero supported texture formats".to_string())?;

            let present_mode = if vsync {
                wgpu::PresentMode::Fifo
            } else {
                caps.present_modes
                    .iter()
                    .copied()
                    .find(|m| *m == wgpu::PresentMode::Mailbox || *m == wgpu::PresentMode::Immediate)
                    .unwrap_or(wgpu::PresentMode::Fifo)
            };

            let alpha_mode = caps
                .alpha_modes
                .first()
                .copied()
                .unwrap_or(wgpu::CompositeAlphaMode::Opaque);

            let safe_width = width.max(1);
            let safe_height = height.max(1);

            let config = wgpu::SurfaceConfiguration {
                usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
                format,
                width: safe_width,
                height: safe_height,
                present_mode,
                desired_maximum_frame_latency: 2,
                alpha_mode,
                view_formats: vec![],
            };
            surface.configure(&device, &config);

            let depth_view = Self::create_depth_view(&device, safe_width, safe_height);

            let (vertices, indices) = build_voxel_chunk();
            let vertex_bytes = bytemuck::cast_slice(&vertices);
            let vertex_buffer = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("voxel_vertex_buffer"),
                size: vertex_bytes.len() as u64,
                usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            queue.write_buffer(&vertex_buffer, 0, vertex_bytes);

            let index_bytes = bytemuck::cast_slice(&indices);
            let index_buffer = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("voxel_index_buffer"),
                size: index_bytes.len() as u64,
                usage: wgpu::BufferUsages::INDEX | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            queue.write_buffer(&index_buffer, 0, index_bytes);

            let uniform_buffer = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("camera_uniform_buffer"),
                size: size_of::<CameraUniform>() as u64,
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });

            let bind_group_layout =
                device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("camera_bind_group_layout"),
                    entries: &[wgpu::BindGroupLayoutEntry {
                        binding: 0,
                        visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
                        ty: wgpu::BindingType::Buffer {
                            ty: wgpu::BufferBindingType::Uniform,
                            has_dynamic_offset: false,
                            min_binding_size: None,
                        },
                        count: None,
                    }],
                });

            let uniform_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("camera_bind_group"),
                layout: &bind_group_layout,
                entries: &[wgpu::BindGroupEntry {
                    binding: 0,
                    resource: uniform_buffer.as_entire_binding(),
                }],
            });

            let shader_module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some("voxel_shader_wgsl"),
                source: wgpu::ShaderSource::Wgsl(VOXEL_SHADER_WGSL.into()),
            });

            let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("voxel_pipeline_layout"),
                bind_group_layouts: &[&bind_group_layout],
                push_constant_ranges: &[],
            });

            let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("voxel_render_pipeline"),
                layout: Some(&pipeline_layout),
                vertex: wgpu::VertexState {
                    module: &shader_module,
                    entry_point: Some("vs_main"),
                    compilation_options: wgpu::PipelineCompilationOptions::default(),
                    buffers: &[Vertex::LAYOUT],
                },
                primitive: wgpu::PrimitiveState {
                    topology: wgpu::PrimitiveTopology::TriangleList,
                    strip_index_format: None,
                    front_face: wgpu::FrontFace::Ccw,
                    cull_mode: Some(wgpu::Face::Back),
                    unclipped_depth: false,
                    polygon_mode: wgpu::PolygonMode::Fill,
                    conservative: false,
                },
                depth_stencil: Some(wgpu::DepthStencilState {
                    format: DEPTH_FORMAT,
                    depth_write_enabled: true,
                    depth_compare: wgpu::CompareFunction::Less,
                    stencil: wgpu::StencilState::default(),
                    bias: wgpu::DepthBiasState::default(),
                }),
                multisample: wgpu::MultisampleState {
                    count: 1,
                    mask: !0,
                    alpha_to_coverage_enabled: false,
                },
                fragment: Some(wgpu::FragmentState {
                    module: &shader_module,
                    entry_point: Some("fs_main"),
                    compilation_options: wgpu::PipelineCompilationOptions::default(),
                    targets: &[Some(wgpu::ColorTargetState {
                        format: config.format,
                        blend: Some(wgpu::BlendState::REPLACE),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                }),
                multiview: None,
                cache: None,
            });

            let shader_boost = if shader_enabled {
                match shader_quality {
                    "ultra" => 1.0,
                    "high" => 0.85,
                    "medium" => 0.65,
                    _ => 0.45,
                }
            } else {
                0.0
            };

            Ok(Self {
                surface,
                device,
                queue,
                config,
                pipeline,
                vertex_buffer,
                index_buffer,
                index_count: indices.len() as u32,
                uniform_buffer,
                uniform_bind_group,
                depth_view,
                shader_boost,
            })
        }
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        let w = width.max(1);
        let h = height.max(1);
        if self.config.width == w && self.config.height == h {
            return;
        }
        self.config.width = w;
        self.config.height = h;
        self.surface.configure(&self.device, &self.config);
        self.depth_view = Self::create_depth_view(&self.device, w, h);
    }

    pub fn render(&mut self, camera: &CameraState, elapsed_secs: f32) -> Result<(), String> {
        let aspect = self.config.width as f32 / self.config.height.max(1) as f32;
        let view_proj = camera.view_proj(aspect);

        let sun_angle = elapsed_secs * 0.15;
        let sun_dir = Vec3::new(0.45 * sun_angle.cos(), 0.82, 0.35 * sun_angle.sin()).normalize();

        let sky = if self.shader_boost > 0.0 {
            [0.42, 0.66, 0.94, 1.0]
        } else {
            [0.50, 0.72, 0.95, 1.0]
        };

        let uniform = CameraUniform {
            view_proj: view_proj.to_cols_array_2d(),
            sun_dir: [sun_dir.x, sun_dir.y, sun_dir.z, 0.0],
            fog_color: sky,
            camera_pos: [camera.position.x, camera.position.y, camera.position.z, 1.0],
            params: [elapsed_secs, self.shader_boost, aspect, 0.0],
        };
        self.queue
            .write_buffer(&self.uniform_buffer, 0, bytemuck::bytes_of(&uniform));

        let output = match self.surface.get_current_texture() {
            Ok(frame) => frame,
            Err(wgpu::SurfaceError::Lost | wgpu::SurfaceError::Outdated) => {
                self.surface.configure(&self.device, &self.config);
                return Ok(());
            }
            Err(wgpu::SurfaceError::Timeout) => return Ok(()),
            Err(err) => return Err(format!("Surface error: {err}")),
        };

        let view = output
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("voxel_frame_encoder"),
            });

        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("voxel_render_pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: sky[0] as f64,
                            g: sky[1] as f64,
                            b: sky[2] as f64,
                            a: 1.0,
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                    view: &self.depth_view,
                    depth_ops: Some(wgpu::Operations {
                        load: wgpu::LoadOp::Clear(1.0),
                        store: wgpu::StoreOp::Store,
                    }),
                    stencil_ops: None,
                }),
                timestamp_writes: None,
                occlusion_query_set: None,
            });

            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &self.uniform_bind_group, &[]);
            pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
            pass.set_index_buffer(self.index_buffer.slice(..), wgpu::IndexFormat::Uint32);
            pass.draw_indexed(0..self.index_count, 0, 0..1);
        }

        self.queue.submit(std::iter::once(encoder.finish()));
        output.present();
        Ok(())
    }

    fn create_depth_view(device: &wgpu::Device, width: u32, height: u32) -> wgpu::TextureView {
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("voxel_depth_texture"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: DEPTH_FORMAT,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            view_formats: &[],
        });
        texture.create_view(&wgpu::TextureViewDescriptor::default())
    }
}

#[derive(Copy, Clone, PartialEq, Eq)]
enum Block {
    Air,
    Grass,
    Dirt,
    Stone,
    Sand,
    Water,
    Wood,
    Leaves,
}

impl Block {
    fn color(self) -> [f32; 3] {
        match self {
            Block::Air => [0.0, 0.0, 0.0],
            Block::Grass => [0.33, 0.67, 0.25],
            Block::Dirt => [0.51, 0.35, 0.22],
            Block::Stone => [0.47, 0.49, 0.51],
            Block::Sand => [0.85, 0.80, 0.56],
            Block::Water => [0.16, 0.47, 0.82],
            Block::Wood => [0.42, 0.28, 0.16],
            Block::Leaves => [0.22, 0.53, 0.20],
        }
    }
}

fn build_voxel_chunk() -> (Vec<Vertex>, Vec<u32>) {
    const SIZE_X: usize = 24;
    const SIZE_Y: usize = 16;
    const SIZE_Z: usize = 24;

    let mut grid = vec![Block::Air; SIZE_X * SIZE_Y * SIZE_Z];
    let idx = |x: usize, y: usize, z: usize| -> usize { (y * SIZE_Z + z) * SIZE_X + x };

    for x in 0..SIZE_X {
        for z in 0..SIZE_Z {
            let fx = x as f32 - (SIZE_X as f32 * 0.5);
            let fz = z as f32 - (SIZE_Z as f32 * 0.5);
            let wave = (fx * 0.32).sin() * 2.1 + (fz * 0.28).cos() * 1.9 + ((fx + fz) * 0.18).sin();
            let height = (5.0 + wave).round().clamp(2.0, 10.0) as usize;

            for y in 0..=height {
                let block = if y == height {
                    if height <= 3 {
                        Block::Sand
                    } else {
                        Block::Grass
                    }
                } else if y + 2 >= height {
                    Block::Dirt
                } else {
                    Block::Stone
                };
                grid[idx(x, y, z)] = block;
            }

            if height < 3 {
                for y in (height + 1)..=3 {
                    grid[idx(x, y, z)] = Block::Water;
                }
            }
        }
    }

    // Add two stylized voxel trees on higher ground.
    for &(tx, tz) in &[(6usize, 7usize), (17usize, 15usize)] {
        if let Some(top_y) = (0..SIZE_Y)
            .rev()
            .find(|&y| grid[idx(tx, y, tz)] == Block::Grass)
        {
            for dy in 1..=3 {
                if top_y + dy < SIZE_Y {
                    grid[idx(tx, top_y + dy, tz)] = Block::Wood;
                }
            }
            for lx in tx.saturating_sub(2)..=(tx + 2).min(SIZE_X - 1) {
                for lz in tz.saturating_sub(2)..=(tz + 2).min(SIZE_Z - 1) {
                    for ly in (top_y + 3)..=(top_y + 5).min(SIZE_Y - 1) {
                        let dist = lx.abs_diff(tx) + lz.abs_diff(tz) + ly.abs_diff(top_y + 4);
                        if dist <= 3 && grid[idx(lx, ly, lz)] == Block::Air {
                            grid[idx(lx, ly, lz)] = Block::Leaves;
                        }
                    }
                }
            }
        }
    }

    let mut vertices = Vec::with_capacity(8192);
    let mut indices = Vec::with_capacity(12288);

    let faces: [([i32; 3], [[f32; 3]; 4], [f32; 3]); 6] = [
        // +Y (top)
        (
            [0, 1, 0],
            [
                [0.0, 1.0, 1.0],
                [1.0, 1.0, 1.0],
                [1.0, 1.0, 0.0],
                [0.0, 1.0, 0.0],
            ],
            [0.0, 1.0, 0.0],
        ),
        // -Y (bottom)
        (
            [0, -1, 0],
            [
                [0.0, 0.0, 0.0],
                [1.0, 0.0, 0.0],
                [1.0, 0.0, 1.0],
                [0.0, 0.0, 1.0],
            ],
            [0.0, -1.0, 0.0],
        ),
        // +X
        (
            [1, 0, 0],
            [
                [1.0, 0.0, 1.0],
                [1.0, 0.0, 0.0],
                [1.0, 1.0, 0.0],
                [1.0, 1.0, 1.0],
            ],
            [1.0, 0.0, 0.0],
        ),
        // -X
        (
            [-1, 0, 0],
            [
                [0.0, 0.0, 0.0],
                [0.0, 0.0, 1.0],
                [0.0, 1.0, 1.0],
                [0.0, 1.0, 0.0],
            ],
            [-1.0, 0.0, 0.0],
        ),
        // +Z
        (
            [0, 0, 1],
            [
                [0.0, 0.0, 1.0],
                [1.0, 0.0, 1.0],
                [1.0, 1.0, 1.0],
                [0.0, 1.0, 1.0],
            ],
            [0.0, 0.0, 1.0],
        ),
        // -Z
        (
            [0, 0, -1],
            [
                [1.0, 0.0, 0.0],
                [0.0, 0.0, 0.0],
                [0.0, 1.0, 0.0],
                [1.0, 1.0, 0.0],
            ],
            [0.0, 0.0, -1.0],
        ),
    ];

    let half_x = SIZE_X as f32 * 0.5;
    let half_z = SIZE_Z as f32 * 0.5;

    for y in 0..SIZE_Y {
        for z in 0..SIZE_Z {
            for x in 0..SIZE_X {
                let block = grid[idx(x, y, z)];
                if block == Block::Air {
                    continue;
                }
                let color = block.color();

                for (offset, corners, normal) in &faces {
                    let nx = x as i32 + offset[0];
                    let ny = y as i32 + offset[1];
                    let nz = z as i32 + offset[2];

                    let neighbor_solid = if nx >= 0
                        && nx < SIZE_X as i32
                        && ny >= 0
                        && ny < SIZE_Y as i32
                        && nz >= 0
                        && nz < SIZE_Z as i32
                    {
                        grid[idx(nx as usize, ny as usize, nz as usize)] != Block::Air
                    } else {
                        false
                    };

                    if neighbor_solid {
                        continue;
                    }

                    let base = vertices.len() as u32;
                    for corner in corners {
                        vertices.push(Vertex {
                            position: [
                                x as f32 - half_x + corner[0],
                                y as f32 + corner[1],
                                z as f32 - half_z + corner[2],
                            ],
                            color,
                            normal: *normal,
                        });
                    }
                    indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
                }
            }
        }
    }

    (vertices, indices)
}
