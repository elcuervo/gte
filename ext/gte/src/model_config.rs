#[derive(Debug, Clone, Copy)]
pub enum ExtractorMode {
    Token(usize),
    MeanPool,
    Raw,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PaddingMode {
    #[default]
    Auto,
    BatchLongest,
    Fixed,
}

#[derive(Debug, Clone)]
pub struct ModelConfig {
    pub max_length: usize,
    pub padding_mode: PaddingMode,
    pub output_tensor: String,
    pub mode: ExtractorMode,
    pub with_type_ids: bool,
    pub with_attention_mask: bool,
    pub num_threads: usize,
    pub optimization_level: u8,
    pub execution_providers: Option<String>,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct ModelLoadOverrides<'a> {
    pub model_name: Option<&'a str>,
    pub output_tensor: Option<&'a str>,
    pub max_length: Option<usize>,
    pub padding: Option<&'a str>,
    pub execution_providers: Option<&'a str>,
}
