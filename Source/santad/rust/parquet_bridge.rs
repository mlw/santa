// Copyright 2025 North Pole Security, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

use cxx::CxxString;
use std::path::Path;

use crate::santa_parquet::ExecBuilder;
use crate::traits::TableBuilder;
use crate::{spool, telemetry};

pub struct ExecEventBuilder<'a> {
    writer: telemetry::writer::Writer<ExecBuilder<'a>>,
}

impl<'a> ExecEventBuilder<'a> {
    pub fn new(spool_path: &Path, batch_size: usize) -> Self {
        Self {
            writer: telemetry::writer::Writer::new(
                batch_size,
                spool::writer::Writer::new("exec", spool_path, None),
                ExecBuilder::new(0, 0, 0, 0),
            ),
        }
    }

    pub fn flush(&mut self) -> anyhow::Result<()> {
        self.writer.flush()
    }

    pub fn autocomplete(&mut self) -> anyhow::Result<()> {
        self.writer.autocomplete()?;
        Ok(())
    }

    pub fn set_executable_path(&mut self, path: &CxxString, truncated: bool) {
        self.writer
            .table_builder()
            .executable_path()
            .append_path(path.to_string());
        self.writer
            .table_builder()
            .executable_path()
            .append_truncated(truncated);
    }
}

pub fn new_exec_builder<'a>(spool_path: &CxxString) -> Box<ExecEventBuilder<'a>> {
    let builder = Box::new(ExecEventBuilder::new(
        Path::new(spool_path.to_string().as_str()),
        1000,
    ));

    // println!("exec telemetry spool: {:?}", builder.writer.path());

    builder
}

#[cxx::bridge(namespace = "santa")]
mod ffi {
    extern "Rust" {
        type ExecEventBuilder<'a>;
        // type CommonBuilder<'a>;

        unsafe fn new_exec_builder<'a>(spool_path: &CxxString) -> Box<ExecEventBuilder<'a>>;
        unsafe fn autocomplete<'a>(self: &mut ExecEventBuilder<'a>) -> Result<()>;

        unsafe fn set_executable_path<'a>(
            self: &mut ExecEventBuilder<'a>,
            path: &CxxString,
            truncated: bool,
        );
    }
}
