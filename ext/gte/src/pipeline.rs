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
        let input_ids_view: ArrayView2<'_, i64> = ArrayView2::from_shape(
            (tokenized.rows, tokenized.cols),
            tokenized.input_ids.as_slice(),
        )?;
        let attention_mask: ArrayView2<'_, i64> = ArrayView2::from_shape(
            (tokenized.rows, tokenized.cols),
            tokenized.attn_masks.as_slice(),
        )?;

        let mut inputs = Vec::with_capacity(2 + usize::from(tokenized.type_ids.is_some()));
        inputs.push((
            "input_ids",
            SessionInputValue::from(TensorRef::from_array_view(input_ids_view)?),
        ));

        if with_attention_mask {
            inputs.push((
                "attention_mask",
                SessionInputValue::from(TensorRef::from_array_view(attention_mask)?),
            ));
        }

        if let Some(type_ids) = tokenized.type_ids.as_deref() {
            let type_ids_view: ArrayView2<'_, i64> =
                ArrayView2::from_shape((tokenized.rows, tokenized.cols), type_ids)?;
            inputs.push((
                "token_type_ids",
                SessionInputValue::from(TensorRef::from_array_view(type_ids_view)?),
            ));
        }

        Ok(Self {
            inputs,
            attention_mask,
        })
    }
}

pub fn extract_output_tensor<'a>(
    outputs: &'a ort::session::SessionOutputs<'_>,
    output_name: &str,
) -> Result<ArrayViewD<'a, f32>> {
    let tensor_value = outputs.get(output_name).ok_or_else(|| {
        GteError::Inference(format!(
            "output tensor '{}' not found in model outputs",
            output_name
        ))
    })?;
    Ok(tensor_value.try_extract_array::<f32>()?)
}
