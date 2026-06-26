use crate::error::{GteError, Result};
use crate::tokenizer::Tokenized;
use ndarray::{ArrayView2, ArrayViewD};
use ort::session::SessionInputValue;
use ort::value::TensorRef;

pub struct InputTensors<'a> {
    pub inputs: Vec<(&'static str, SessionInputValue<'a>)>,
    pub attention_mask: ArrayView2<'a, i64>,
}

impl<'a> InputTensors<'a> {
    pub fn from_tokenized(tokenized: &'a Tokenized, with_attention_mask: bool) -> Result<Self> {
        let input_ids_view = tokenized.input_ids.view();
        let attention_mask = tokenized.attn_masks.view();

        let mut inputs = Vec::with_capacity(2);

        if with_attention_mask {
            inputs.push(("input_ids", SessionInputValue::from(TensorRef::from_array_view(input_ids_view)?)));
            inputs.push(("attention_mask", SessionInputValue::from(TensorRef::from_array_view(attention_mask)?)));
        } else {
            inputs.push(("input_ids", SessionInputValue::from(TensorRef::from_array_view(input_ids_view)?)));
        }

        if let Some(ref type_ids) = tokenized.type_ids {
            let type_ids_view = type_ids.view();
            inputs.push(("token_type_ids", SessionInputValue::from(TensorRef::from_array_view(type_ids_view)?)));
        }

        Ok(Self { inputs, attention_mask })
    }
}

pub fn extract_output_tensor<'a>(
    outputs: &'a ort::session::SessionOutputs<'_>,
    output_name: &str,
) -> Result<ArrayViewD<'a, f32>> {
    let tensor_value = outputs
        .get(output_name)
        .ok_or_else(|| GteError::Inference(format!("output tensor '{output_name}' not found in model outputs")))?;
    Ok(tensor_value.try_extract_array::<f32>()?)
}
