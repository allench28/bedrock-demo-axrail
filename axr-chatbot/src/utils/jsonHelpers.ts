export const isJSONString = async (str: string) => {
  try {
    JSON.parse(str);
    return true;
  } catch (error) {
    return false;
  }
};

export const tryParseJSON = async (str: string) => {
  try {
    const json = JSON.parse(str);
    return json;
  } catch (error) {
    return str;
  }
};
