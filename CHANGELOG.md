# CHANGELOG

## 0.6.1 (Sep 29, 2013)

* New Features
    * leo_rpc:cast/4
* Improved
    * Make error msgs understandable
    * Implemented max request per one session
    * make invoking a cancel message sync(call) instead of async(cast)
* Fixed Bugs
    * Parse errors can occur in case of including CRLF|LF in a header block
    * leo_rpc:nb_yield I/F was wrong
    * Invalid ets records may have been existing
    * Handle errors properly when protocol errors occurred
    * Handle large receive data which size exceeds the size of one request
    * When timeout occured at a rpc client, a rpc server may respond to a wrong client(another erlang process)
    * Deffered function calls can be accumulated when gen_server shut-downed
    * Port type was wrong(list() -> integer)


## 0.6.0 (Jul 29, 2013)

* Improvement
    * Performance tuning
    * Able to set listening timeout
* Bug Fixed
    * Fixed incorrect return value in "leo_rpc_server_listener"
* Other
    * Spent a lot of time on the functional-test and the stress-test


## 0.4.3 (Jul 24, 2013)

* Improvement
    * Performance tuning
* Bug Fixed
    * Fixed the part of parsing data


## 0.4.2 (Jul 17, 2013)

* Bug Fixed
    * Fixed possibility of not receiving whole data


## 0.4.1 (Jul 12, 2013)

* Improvement
    * Supported *node-function* and *nodes-function*
    * Improvement async-call and nb-yield


## 0.4.0 (Jul 9, 2013)

* Initial release
