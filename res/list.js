function increase_progress(id)
{
	alert(id);
}

function click_tag(el)
{
	if(el.childNodes.length != 1) {
		return;
	}
	const tagstr = el.childNodes[0].textContent.trim();
	let url = new URL(document.location);
	const params = url.searchParams;
	let remove = false;
	const keep = [];
	for(const [key, value] of params) {
		if(key === "i") {
			if(value === tagstr) {
				remove = true;
			}
			else {
				keep.push(value);
			}
		}
	}
	if(remove === false) {
		keep.push(tagstr);
	}
	if(keep.length === 0) {
		params.delete("i");
	}
	else {
		params.set("i", keep[0]);
		for(let i = 1; i < keep.length; i++) {
			params.append("i", keep[i]);
		}
	}
	window.location.assign(url.search);
}

function make_tags()
{
	var list = document.getElementById('list');
	for(const tag of list.getElementsByClassName('td_tag')) {
		if(tag.childNodes.length != 1) {
			continue;
		}
		const tagstr = tag.childNodes[0].textContent;
		if(tagstr === null) {
			continue;
		}
		const newhtml = [];
		for(const tagname of tagstr.split(',')) {
			newhtml.push('<a href="#" onclick="click_tag(this);return false;">' + tagname + '</a>')
		}
		tag.innerHTML = newhtml.join(', ');
	}
}
