const axios = require('axios');

module.exports = async function (context, req) {
    context.log('JavaScript HTTP trigger function processed a request.');
    const laurl = process.env.LA_URL
    context.log(`preaxios:${laurl}`)
    const res = await axios.post(`${laurl}`);
    context.log(res.data)
    context.log("postaxios")
    context.res = {
        // status: 200, /* Defaults to 200 */
        body: res.data
    };
}