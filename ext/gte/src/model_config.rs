#[derive(Debug, Clone, Copy)]
pub enum ExtractorMode {
    Token(usize),
    MeanPool,
    Raw,
}

#[derive(Debug, Clone)]
pub struct ModelConfig {
    pub max_length: usize,
    pub output_tensor: String,
    pub mode: ExtractorMode,
    pub with_type_ids: bool,
    pub with_attention_mask: bool,
    pub num_threads: usize,
    pub optimization_level: u8,
    pub execution_providers: Option<String>,
}
