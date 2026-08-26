//! Candle-independent AQuA command and tensor metadata.
//! `//!`는 현재 모듈 전체에 대한 문서 주석.

use std::{error::Error, fmt}; // std::error::Error와 std::fmt를 현재 scope로 가져옴.

#[derive(Clone, Copy, Debug, Eq, PartialEq)] // Clone, 자동 복사(Copy), Debug 출력, ==/!= 비교 지원.
pub enum AquaDType {                         // enum: 여러 variant 중 하나의 값을 가지는 타입.
    F32,
    I4,
    I8,
    I16,
    I32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TensorDesc {                      // struct: 여러 field를 하나의 타입으로 묶음.
    pub dtype: AquaDType,                    // pub: 다른 모듈에서도 접근 가능.
    pub shape: Vec<usize>,                   // Vec<T>: heap에 저장되는 동적 배열. usize는 크기/인덱스용 정수.
    pub len: usize,                          // tensor 전체 element 개수.
}
// Vec은 heap 메모리를 소유하므로 Copy가 아님.
// 따라서 TensorDesc도 Copy를 derive하지 않고, 복사가 필요하면 clone()을 사용.

impl TensorDesc {                            // impl: TensorDesc에 함수/메서드를 구현.
    pub fn new(
        dtype: AquaDType,                    // 함수 인자는 `이름: 타입`.
        shape: Vec<usize>,
    ) -> Result<Self, TensorDescError> {      // Self = TensorDesc, Result<T, E> = 성공 Ok(T) / 실패 Err(E).

        let len = shape                      // let: 지역 변수 binding. 바깥쪽 len은 최종 element count.
            .iter()                          // shape의 원소를 reference(&usize) 형태로 순회.
            .try_fold(
                1_usize,                     // 누적값의 초기값. `1_usize`는 usize 타입의 숫자 1.
                |len, dim|                   // closure. len=누적값, dim=현재 shape 원소(&usize).
                    len.checked_mul(*dim),   // *dim으로 dereference. overflow 없으면 Some, 있으면 None.
            )
            .ok_or(                          // Option<T> -> Result<T, E> 변환.
                TensorDescError::ElementCountOverflow,
            )?;                              // Ok이면 값을 꺼내고, Err이면 현재 함수에서 즉시 반환.

        Ok(Self { dtype, shape, len })        // Self = TensorDesc. 성공 결과를 Ok(...)로 반환.
                                             // field명과 변수명이 같아서 `dtype: dtype` 등을 축약.
                                             // 마지막 표현식이라 세미콜론 없이 함수 반환값이 됨.
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TensorDescError {
    ElementCountOverflow,                    // shape 곱셈 중 usize 범위를 초과한 경우.
}

impl fmt::Display for TensorDescError {       // `impl Trait for Type`: Display trait을 구현.
    fn fmt(
        &self,                               // &self: 현재 값을 immutable reference로 빌림.
        formatter: &mut fmt::Formatter<'_>,  // &mut: 수정 가능한 reference, '_는 lifetime 추론.
    ) -> fmt::Result {                       // formatting 성공/실패를 나타내는 Result.

        match self {                         // match: enum variant에 따른 pattern matching.
            Self::ElementCountOverflow =>    // Self = TensorDescError.
                formatter.write_str(
                    "tensor element count overflow",
                ),
        }
    }
}

impl Error for TensorDescError {}             // 표준 Error trait 구현. 추가 구현이 없어 body는 비어 있음.