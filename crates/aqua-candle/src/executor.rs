use crate::FixedStripePlanner;
use aqua_exsia::{dequantize_dense, ExsiaConfig, ExsiaInput, ReferenceExsia};
use aqua_runtime::HostTensor;
use candle_core::backend::{BackendDevice, BackendStorage};
use candle_core::cpu_backend::CpuDevice;
use candle_core::{AquaDispatch, AquaMatMulRequest, CpuStorage, DType, Error, Layout, Shape};

/// Candle matmul executor for the integration-stage dense Q-only path.
///
/// The left operand is quantized by ExSIA and reconstructed with
/// `dequantize_dense`, which intentionally excludes residual correction. Both
/// request layouts are materialized in exact logical order before CPU matmul.
#[derive(Clone, Debug)]
pub struct DenseQOnlyAquaExecutor {
    config: ExsiaConfig,
    planner: FixedStripePlanner,
}

impl DenseQOnlyAquaExecutor {
    pub const fn new(config: ExsiaConfig, planner: FixedStripePlanner) -> Self {
        Self { config, planner }
    }
}

impl candle_core::AquaExecutor for DenseQOnlyAquaExecutor {
    fn name(&self) -> &'static str {
        "dense-q-only"
    }

    fn matmul(
        &self,
        request: AquaMatMulRequest<'_>,
    ) -> candle_core::Result<AquaDispatch<CpuStorage>> {
        let lhs_dtype = request.lhs.dtype();
        let rhs_dtype = request.rhs.dtype();
        if lhs_dtype != rhs_dtype
            || !matches!(
                lhs_dtype,
                DType::F16 | DType::BF16 | DType::F32 | DType::F64
            )
        {
            return Ok(AquaDispatch::Fallback);
        }

        let (lhs_f32, lhs_layout) = materialize_contiguous_f32(request.lhs, request.lhs_layout)?;
        let CpuStorage::F32(lhs_values) = lhs_f32 else {
            return Err(Error::msg("AQuA expected contiguous F32 CPU storage"));
        };
        let host = HostTensor::f32(lhs_layout.dims().to_vec(), lhs_values).map_err(Error::wrap)?;
        let plan = self.planner.plan(&host.desc.shape).map_err(Error::wrap)?;
        let input = ExsiaInput::new(&host, self.config).map_err(Error::wrap)?;
        let output = ReferenceExsia::new()
            .execute(&input, &plan)
            .map_err(Error::wrap)?;
        let dense_q = dequantize_dense(&output, &plan).map_err(Error::wrap)?;

        let lhs_q_storage = CpuStorage::F32(dense_q.data);
        let lhs_q_layout = Layout::contiguous(Shape::from(dense_q.desc.shape));
        let (rhs_f32, rhs_f32_layout) =
            materialize_contiguous_f32(request.rhs, request.rhs_layout)?;
        let result_f32 =
            lhs_q_storage.matmul(&rhs_f32, request.bmnk, &lhs_q_layout, &rhs_f32_layout)?;

        let result = if lhs_dtype == DType::F32 {
            result_f32
        } else {
            let (batch, m, n, _) = request.bmnk;
            let output_len = batch
                .checked_mul(m)
                .and_then(|value| value.checked_mul(n))
                .ok_or_else(|| Error::msg("AQuA matmul output size overflow"))?;
            let output_layout = Layout::contiguous(Shape::from(vec![output_len]));
            result_f32.to_dtype(&output_layout, lhs_dtype)?
        };

        Ok(AquaDispatch::Executed(result))
    }
}

fn materialize_contiguous_f32(
    storage: &CpuStorage,
    layout: &Layout,
) -> candle_core::Result<(CpuStorage, Layout)> {
    let mut contiguous = CpuDevice.zeros_impl(layout.shape(), storage.dtype())?;
    storage.copy_strided_src(&mut contiguous, 0, layout)?;
    let contiguous_layout = Layout::contiguous(layout.shape().clone());
    let f32_storage = if contiguous.dtype() == DType::F32 {
        contiguous
    } else {
        contiguous.to_dtype(&contiguous_layout, DType::F32)?
    };

    Ok((f32_storage, contiguous_layout))
}
