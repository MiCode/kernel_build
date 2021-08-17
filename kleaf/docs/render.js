/*
 * Copyright (C) 2021 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

function get(url, successFn, failFn) {
    var request = new XMLHttpRequest()
    request.open("GET", url, true);
    request.onreadystatechange = function () {
        if (request.readyState === XMLHttpRequest.DONE) {
            if (request.status === 200) {
                successFn(request);
            } else {
                failFn(request);
            }
        }
    }
    request.send(null)
}

function showMarkdownFile(responseText, file) {
    const headerLevelStart = 1;

    var converter = new showdown.Converter();
    converter.setOption("customizedHeaderId", true);
    converter.setOption("ghCompatibleHeaderId", true);
    converter.setOption("headerLevelStart", headerLevelStart);
    document.getElementById("div-file-contents").innerHTML = converter.makeHtml(responseText);

    // Show file name
    document.getElementById("headline-file-name").innerText = file;
    // Generate table of contents
    var h2Elements = document.getElementById("div-file-contents").getElementsByTagName("h" + headerLevelStart)
    var sampleToc = document.getElementById("div-sample-toc")
    var toc = document.getElementById("div-toc-contents")
    for (let i = 0; i < h2Elements.length; i++) {
        var clone = sampleToc.cloneNode(true)
        var link = clone.getElementsByTagName("a")[0];
        link.href = "#" + h2Elements[i].id
        link.innerText = h2Elements[i].id
        toc.appendChild(clone)
    }

    var fileName = document.getElementById("headline-file-name")
    fileName.hidden = false;
}

document.addEventListener("DOMContentLoaded", function () {
    // Show directory
    get(new URL("directory.html.frag", document.location).href, function(request) {
        document.getElementById("div-directory-frag").innerHTML = request.responseText;
    }, function(request) {
        document.getElementById("div-directory-frag").innerText = "Failed to get directory.html.frag"
    });

    const params = new URLSearchParams(window.location.search);
    const file = params.get("file")
    if (!file) {
        return;
    }
    if (!file.endsWith(".md")) {
        document.body.innerText = "Invalid param for file";
        return;
    }
    get(new URL(file, document.location).href, function (request) {
        showMarkdownFile(request.responseText, file);
    }, function (request) {
        document.body.innerText = request.status + " " + request.statusText
    })
});
