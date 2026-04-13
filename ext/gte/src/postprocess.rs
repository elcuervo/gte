use crate::error::{GteError, Result};
use ndarray::{Array2, ArrayView2, ArrayView3};

pub fn mean_pool(
    hidden_states: ArrayView3<'_, f32>,
    attention_mask: ArrayView2<'_, i64>,
) -> Result<Array2<f32>> {
    let (batch, seq, dim) = hidden_states.dim();
    if attention_mask.dim() != (batch, seq) {
        return Err(GteError::Inference(format!(
            "attention mask shape {:?} does not match hidden state shape ({batch}, {seq}, {dim})",
            attention_mask.dim()
        )));
    }

    let mut pooled = Array2::<f32>::zeros((batch, dim));

    if let (Some(hidden), Some(mask), Some(output)) = (
        hidden_states.as_slice_memory_order(),
        attention_mask.as_slice_memory_order(),
        pooled.as_slice_memory_order_mut(),
    ) {
        mean_pool_contiguous(hidden, mask, output, batch, seq, dim);
        return Ok(pooled);
    }

    for batch_index in 0..batch {
        let mut weight_sum = 0.0f32;
        for token_index in 0..seq {
            let weight = attention_mask[[batch_index, token_index]];
            if weight <= 0 {
                continue;
            }

            let weight = weight as f32;
            for dim_index in 0..dim {
                pooled[[batch_index, dim_index]] +=
                    hidden_states[[batch_index, token_index, dim_index]] * weight;
            }
            weight_sum += weight;
        }

        if weight_sum > 0.0 {
            let inverse = weight_sum.recip();
            pooled
                .row_mut(batch_index)
                .map_inplace(|value| *value *= inverse);
        }
    }

    Ok(pooled)
}

pub fn normalize_l2(mut embeddings: Array2<f32>) -> Array2<f32> {
    let cols = embeddings.ncols();
    if let Some(data) = embeddings.as_slice_mut() {
        for row in data.chunks_mut(cols) {
            let norm = row.iter().map(|v| v * v).sum::<f32>().sqrt();
            if norm > 0.0 {
                let inv = norm.recip();
                for v in row.iter_mut() {
                    *v *= inv;
                }
            }
        }
        return embeddings;
    }
    // non-contiguous fallback
    for mut row in embeddings.rows_mut() {
        let norm = row.iter().map(|value| value * value).sum::<f32>().sqrt();
        if norm > 0.0 {
            row.map_inplace(|value| *value *= norm.recip());
        }
    }
    embeddings
}

fn mean_pool_contiguous(
    hidden: &[f32],
    attention_mask: &[i64],
    output: &mut [f32],
    batch: usize,
    seq: usize,
    dim: usize,
) {
    for batch_index in 0..batch {
        let mask_base = batch_index * seq;
        let hidden_base = batch_index * seq * dim;
        let output_row = &mut output[batch_index * dim..(batch_index + 1) * dim];
        let mask_row = &attention_mask[mask_base..mask_base + seq];

        if mask_row.iter().all(|&weight| weight == 1) {
            for token_index in 0..seq {
                let token_base = hidden_base + token_index * dim;
                for dim_index in 0..dim {
                    output_row[dim_index] += hidden[token_base + dim_index];
                }
            }

            let inverse = (seq as f32).recip();
            for value in output_row {
                *value *= inverse;
            }
            continue;
        }

        let mut weight_sum = 0.0f32;

        for token_index in 0..seq {
            let weight = mask_row[token_index];
            if weight <= 0 {
                continue;
            }

            let weight = weight as f32;
            let token_base = hidden_base + token_index * dim;
            for dim_index in 0..dim {
                output_row[dim_index] += hidden[token_base + dim_index] * weight;
            }
            weight_sum += weight;
        }

        if weight_sum > 0.0 {
            let inverse = weight_sum.recip();
            for value in output_row {
                *value *= inverse;
            }
        }
    }
}
